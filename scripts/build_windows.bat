@echo off
REM Two-stage Windows release build (Phase 6 — Flutter frontend + Python engine).
REM
REM   Stage 1  engine sidecar : PyInstaller packaging\engine.spec -> dist\engine_cli\
REM   Stage 2  Flutter app    : flutter build windows --release
REM   Stage 3  bundle         : copy sidecar into <exe dir>\engine\engine_cli.exe
REM             and install to release\Windows\Compresstor\
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
echo ==^> Installing to release\Windows\Compresstor\...
if exist release\Windows\Compresstor rmdir /s /q release\Windows\Compresstor
mkdir release\Windows
xcopy /e /i /q "%APP%" release\Windows\Compresstor >nul

echo.
echo ==^> Update artifact: Compresstor-%VER%-windows.zip + sha256...
set "ZIP=release\Compresstor-%VER%-windows.zip"
if exist "%ZIP%" del "%ZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%APP%\*' -DestinationPath '%ZIP%' -Force"
for /f "delims=" %%h in ('certutil -hashfile "%ZIP%" SHA256 ^| findstr /r "^[0-9a-fA-F]"') do set HASH=%%h
echo %HASH%  Compresstor-%VER%-windows.zip>> release\Compresstor-%VER%.sha256

rmdir /s /q build dist

echo.
echo ==^> Stage 5: Inno Setup installer...
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
if defined SIGN_PFX (
  echo.
  echo ==^> Signing installer with code signing certificate...
  signtool sign /f "%SIGN_PFX%" /p "%SIGN_PWD%" /tr http://timestamp.digicert.com /td sha256 /fd sha256 "release\Compresstor-%VER%-windows-setup.exe"
  if errorlevel 1 echo WARN: Signing failed
) else (
  echo NOTE: Installer is unsigned. Set SIGN_PFX and SIGN_PWD to sign.
)

:done
echo.
echo Done. Artifact: release\Windows\Compresstor\compresstor.exe
echo          Engine:  release\Windows\Compresstor\engine\engine_cli.exe
endlocal
