#!/usr/bin/env python3
"""
Compresstor in-app update applier — runs detached from the main app.

Usage:
    python apply_update.py --platform macos|windows \
        --zip <path-to-downloaded-zip> \
        --target <install-dir-or-app-bundle> \
        --pid <app-pid-to-wait-for> \
        [--exe-name <binary-name>]

Flow:
  1. Wait for the app process (--pid) to exit (polls every 0.5s, max 30s).
  2. Extract the zip into a temp dir.
  3. Swap: remove the old install, move the new one in.
     - macOS: strips quarantine xattr, replaces .app bundle.
     - Windows: replaces the install directory contents.
  4. Relaunch the new binary.
  5. Clean up temp files and exit.

On macOS, if the target is in /Applications (or otherwise not writable),
the script uses osascript to elevate with admin privileges.

Exit codes:
  0 = success (app relaunched)
  1 = error (logged to stderr and to a .update-error.log next to this script)
"""

import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path


def log(msg: str) -> None:
    print(f"[compresstor-update] {msg}", flush=True)


def wait_for_exit(pid: int, timeout: float = 30.0) -> None:
    """Wait for a process to exit by polling."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not _pid_alive(pid):
            return
        time.sleep(0.5)
    # If still alive after timeout, proceed anyway — the user triggered this.
    log(f"Warning: PID {pid} did not exit within {timeout}s, proceeding.")


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def extract_zip(zip_path: Path, dest: Path) -> None:
    """Extract zip to dest directory."""
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(dest)
    # Restore executable permissions on macOS
    if platform.system() == "Darwin":
        for root, dirs, files in os.walk(dest):
            for f in files:
                fp = os.path.join(root, f)
                st = os.stat(fp)
                # If the file was executable in the zip, ensure it stays so
                os.chmod(fp, st.st_mode | 0o755)


def strip_quarantine(path: Path) -> None:
    """Remove all extended attributes (including quarantine) recursively."""
    try:
        subprocess.run(
            ["xattr", "-cr", str(path)],
            capture_output=True,
        )
    except Exception:
        pass


def needs_elevation(target: Path) -> bool:
    """Check if we can write to the target's parent directory."""
    probe = target.parent / ".compresstor-write-test"
    try:
        probe.write_text("x")
        probe.unlink()
        return False
    except OSError:
        return True


def run_elevated(script: str) -> None:
    """Run a shell command with admin privileges via osascript."""
    result = subprocess.run(
        [
            "osascript",
            "-e",
            f'do shell script "{script}" with administrator privileges',
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Elevated command failed (exit {result.returncode}): {result.stderr.strip()}"
        )


def apply_macos(zip_path: Path, target: Path, exe_name: str) -> Path:
    """
    macOS: extract Compresstor.app from zip, swap it for the running bundle.
    Returns the path to the binary to relaunch.
    """
    tmp = Path(tempfile.mkdtemp(prefix="compresstor-install-"))
    try:
        # Strip quarantine from zip
        strip_quarantine(zip_path)

        # Extract
        extract_zip(zip_path, tmp)

        # Find the .app inside
        new_app = tmp / "Compresstor.app"
        if not new_app.exists():
            # Maybe it's nested or has a different name — look for any .app
            apps = list(tmp.glob("*.app"))
            if apps:
                new_app = apps[0]
            else:
                raise RuntimeError("Update package has no .app bundle inside.")

        # Strip quarantine from extracted bundle
        strip_quarantine(new_app)

        # Swap
        if needs_elevation(target):
            escaped_target = str(target).replace("'", "'\\''")
            escaped_new = str(new_app).replace("'", "'\\''")
            run_elevated(
                f"rm -rf '{escaped_target}' && mv '{escaped_new}' '{escaped_target}' && xattr -cr '{escaped_target}'"
            )
        else:
            if target.exists():
                shutil.rmtree(target)
            shutil.move(str(new_app), str(target))
            # Strip quarantine from the final installed bundle
            strip_quarantine(target)

        binary = target / "Contents" / "MacOS" / exe_name
        if not binary.exists():
            raise RuntimeError(f"New app binary not found at {binary}")
        return binary
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def apply_windows(zip_path: Path, target: Path, exe_name: str) -> Path:
    """
    Windows: extract zip contents, replace the install directory.
    Returns the path to the exe to relaunch.
    """
    tmp = Path(tempfile.mkdtemp(prefix="compresstor-install-"))
    try:
        extract_zip(zip_path, tmp)

        # The zip should contain compresstor.exe at root level
        new_exe = tmp / exe_name
        if not new_exe.exists():
            raise RuntimeError(f"Update package has no {exe_name} inside.")

        # Remove old install directory contents (but keep the dir)
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True, exist_ok=True)

        # Move all extracted contents into target
        for item in tmp.iterdir():
            dest = target / item.name
            shutil.move(str(item), str(dest))

        binary = target / exe_name
        if not binary.exists():
            raise RuntimeError(f"New binary not found at {binary}")
        return binary
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def relaunch(binary: Path) -> None:
    """Start the new binary detached."""
    if platform.system() == "Darwin":
        subprocess.Popen(
            [str(binary)],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    else:
        # Windows: use CREATE_NEW_PROCESS_GROUP + DETACHED_PROCESS
        CREATE_NEW_PROCESS_GROUP = 0x00000200
        DETACHED_PROCESS = 0x00000008
        subprocess.Popen(
            [str(binary)],
            creationflags=CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS,
            close_fds=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Compresstor update applier")
    parser.add_argument("--platform", required=True, choices=["macos", "windows"])
    parser.add_argument("--zip", required=True, help="Path to downloaded update zip")
    parser.add_argument(
        "--target", required=True, help="Install dir (Windows) or .app bundle (macOS)"
    )
    parser.add_argument("--pid", required=True, type=int, help="PID to wait for")
    parser.add_argument(
        "--exe-name", default=None, help="Binary name (default: compresstor.exe or Compresstor)"
    )
    args = parser.parse_args()

    zip_path = Path(args.zip)
    target = Path(args.target)

    if args.exe_name:
        exe_name = args.exe_name
    elif args.platform == "windows":
        exe_name = "compresstor.exe"
    else:
        exe_name = "compresstor"

    try:
        log(f"Waiting for PID {args.pid} to exit...")
        wait_for_exit(args.pid)

        log(f"Applying update from {zip_path} to {target}...")
        if args.platform == "macos":
            binary = apply_macos(zip_path, target, exe_name)
        else:
            binary = apply_windows(zip_path, target, exe_name)

        # Clean up the zip
        try:
            zip_path.unlink(missing_ok=True)
        except Exception:
            pass

        log(f"Relaunching {binary}...")
        relaunch(binary)
        log("Update complete.")
        return 0

    except Exception as e:
        log(f"ERROR: {e}")
        # Write error log next to this script
        try:
            err_log = Path(__file__).parent / ".update-error.log"
            err_log.write_text(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {e}\n")
        except Exception:
            pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
