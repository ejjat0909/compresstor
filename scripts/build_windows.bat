@echo off
REM Build the Compresstor Windows app and copy it into release\Windows\.
REM Run from the repo root on Windows 10/11:  scripts\build_windows.bat
setlocal
cd /d "%~dp0.."

where python >nul 2>nul || (echo Python not found on PATH & exit /b 1)

if not exist .venv (
  echo Creating virtual environment...
  python -m venv .venv
)
call .venv\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r requirements.txt

echo Building Compresstor.exe...
python -m PyInstaller packaging\compresstor.spec --noconfirm

echo Copying to release\Windows\...
if exist release\Windows\Compresstor rmdir /s /q release\Windows\Compresstor
mkdir release\Windows
xcopy /e /i /q dist\Compresstor release\Windows\Compresstor >nul
rmdir /s /q build dist

echo.
echo Done. Artifact: release\Windows\Compresstor\Compresstor.exe
endlocal
