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
echo ==^> Stage 1: engine sidecar (PyInstaller)...
python -m PyInstaller packaging\engine.spec --noconfirm --distpath dist --workpath build
if errorlevel 1 exit /b 1
if not exist dist\engine_cli\engine_cli.exe (
  echo Sidecar build failed & exit /b 1
)

echo.
echo ==^> Stage 2: Flutter release app...
pushd flutter
call flutter build windows --release
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
xcopy /e /i /q dist\engine_cli "%APP%\engine" >nul

echo.
echo ==^> Installing to release\Windows\Compresstor\...
if exist release\Windows\Compresstor rmdir /s /q release\Windows\Compresstor
mkdir release\Windows
xcopy /e /i /q "%APP%" release\Windows\Compresstor >nul
rmdir /s /q build dist

echo.
echo Done. Artifact: release\Windows\Compresstor\compresstor.exe
echo          Engine:  release\Windows\Compresstor\engine\engine_cli.exe
endlocal
