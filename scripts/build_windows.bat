@echo off
REM Two-stage Windows release build (Phase 6 — Flutter frontend + Python engine).
REM
REM   Stage 1  engine sidecar : PyInstaller packaging\engine.spec -> dist\engine_cli\
REM   Stage 2  Flutter app    : flutter build windows --release
REM   Stage 3  bundle         : copy sidecar into <exe dir>\engine\engine_cli.exe
REM   Stage 4  code signing   : sign every bundled EXE (SIGN_PFX/SIGN_PWD)
REM   Stage 5  install        : copy app tree to release\Windows\Compresstor\
REM   Stage 6  installer      : Inno Setup setup.exe (signed + verified)
REM
REM Run from the repo root on Windows 10/11:  scripts\build_windows.bat
REM
REM NOTE: must be run on a machine with Flutter Windows desktop enabled and a
REM Python venv with PyMuPDF + Pillow. EngineClient auto-detects the bundled
REM engine at <exe dir>\engine\engine_cli.exe.
setlocal
cd /d "%~dp0.."

where flutter >nul 2>nul || (echo Flutter not found on PATH & exit /b 1)
where python >nul 2>nul || (echo Python not found on PATH & exit /b 1)

if not exist .venv (
  echo Creating virtual environment...
  python -m venv .venv
)
call .venv\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r requirements.txt
pip install pyinstaller

echo.
echo ==^> Reading version from version.json (single source)...
for /f "usebackq tokens=1,2" %%a in (`python -c "import json;d=json.load(open('version.json'));print(d['version'],d['build'])"`) do (
  set VER=%%a
  set BUILD=%%b
)
echo Version: %VER% (build %BUILD%)
copy /y version.json flutter\assets\version.json >nul

echo.
echo ==^> Stage 1: engine sidecar (PyInstaller)...
python -m PyInstaller packaging\engine.spec --noconfirm --distpath dist --workpath build
if errorlevel 1 exit /b 1
if not exist dist\engine_cli.exe (
  echo Sidecar build failed & exit /b 1
)

echo.
echo ==^> Stage 2: Flutter release app...
pushd flutter
call flutter build windows --release --build-name %VER% --build-number %BUILD%
popd
if errorlevel 1 exit /b 1

set APP=flutter\build\windows\x64\runner\Release
if not exist "%APP%\compresstor.exe" (
  echo Flutter app not produced & exit /b 1
)

echo.
echo ==^> Stage 3: bundle engine sidecar...
if exist "%APP%\engine" rmdir /s /q "%APP%\engine"
mkdir "%APP%\engine"
copy /y dist\engine_cli.exe "%APP%\engine\engine_cli.exe" >nul
copy /y version.json "%APP%\version.json" >nul

echo.
echo ==^> Bundling updater script...
if not exist "%APP%\app\updater" mkdir "%APP%\app\updater"
copy /y app\updater\apply_update.py "%APP%\app\updater\apply_update.py" >nul

echo.
echo ==^> Stage 4: code signing (SmartScreen "Unknown publisher" fix)...
REM Note: the workflow sets SIGN_PFX to an EMPTY string when no cert is
REM configured. "if defined X" is true for an empty-but-set var, so check
REM for non-empty explicitly (or the empty cert path would hard-fail).
if not "%SIGN_PFX%"=="" (
  where signtool >nul 2>nul || (
    echo ERROR: SIGN_PFX is set but signtool was not found on PATH.
    echo Install the Windows SDK (Windows 10 SDK component) or put signtool on PATH.
    exit /b 1
  )
  if not exist "%SIGN_PFX%" (
    echo ERROR: SIGN_PFX points to a missing file: %SIGN_PFX%
    exit /b 1
  )
  REM Sign every bundled EXE (app, engine sidecar, any helper) BEFORE the
  REM installer is built - SmartScreen checks the installed exes too, not
  REM just the setup.exe. /tr + /td sha256 = RFC 3161 timestamped
  REM signature, so the cert can expire without invalidating the build.
  for /r "%APP%" %%f in (*.exe) do (
    echo Signing: %%f
    signtool sign /f "%SIGN_PFX%" /p "%SIGN_PWD%" ^
      /tr http://timestamp.digicert.com /td sha256 /fd sha256 "%%f"
    if errorlevel 1 (
      echo ERROR: signtool failed on %%f
      exit /b 1
    )
  )
  echo All bundled EXEs signed.
) else (
  echo WARN: SIGN_PFX not set - build will be UNSIGNED and Windows will
  echo show "Unknown publisher" in SmartScreen. See
  echo docs\windows-code-signing.md to fix.
)

echo.
echo ==^> Installing to release\Windows\Compresstor\...
if exist release\Windows\Compresstor rmdir /s /q release\Windows\Compresstor
mkdir release\Windows
xcopy /e /i /q "%APP%" release\Windows\Compresstor >nul

echo.
echo ==^> Update artifact: Compresstor-%VER%-windows.zip + sha256...
set "ZIP=release\Compresstor-%VER%-windows.zip"
if exist "%ZIP%" del "%ZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%APP%\*' -DestinationPath '%ZIP%' -Force"
for /f "delims=" %%h in ('powershell -NoProfile -Command "(Get-FileHash '%ZIP%' -Algorithm SHA256).Hash.ToLower()"') do set HASH=%%h
echo %HASH%  Compresstor-%VER%-windows.zip> release\Compresstor-%VER%-windows.sha256

rmdir /s /q build dist

echo.
echo ==^> Stage 6: Inno Setup installer...
where iscc >nul 2>nul || (
  echo WARN: Inno Setup not found - skipping installer. Install from https://jrsoftware.org/isdown.php
  goto :done
)
iscc /DMyAppVersion=%VER% packaging\windows\installer.iss
if errorlevel 1 (
  echo WARN: Installer build failed
  goto :done
)
echo Installer: release\Compresstor-%VER%-windows-setup.exe

REM Sign the installer if a code signing certificate is available.
REM Set SIGN_PFX=path\to\cert.pfx and SIGN_PWD=password to enable.
if not "%SIGN_PFX%"=="" (
  echo.
  echo ==^> Signing installer with code signing certificate...
  signtool sign /f "%SIGN_PFX%" /p "%SIGN_PWD%" /tr http://timestamp.digicert.com /td sha256 /fd sha256 "release\Compresstor-%VER%-windows-setup.exe"
  if errorlevel 1 (
    echo ERROR: installer signing failed
    exit /b 1
  )
  signtool verify /pa /v "release\Compresstor-%VER%-windows-setup.exe" >nul 2>nul && echo OK: installer signature verified || echo WARN: could not verify installer signature
) else (
  echo NOTE: Installer is unsigned. Set SIGN_PFX and SIGN_PWD to sign.
)

:done
echo.
echo Done. Artifact: release\Windows\Compresstor\compresstor.exe
echo          Engine:  release\Windows\Compresstor\engine\engine_cli.exe
endlocal
