@echo off
REM =============================================================================
REM Smash for Sydney - Windows Setup Script  (CMD / batch)
REM =============================================================================
REM Sets up everything to run the Smash for Sydney bot framework on a fresh
REM Windows (x64) install. Idempotent - safe to re-run.
REM
REM Requirements: Windows 10 1803+ (needs curl.exe and tar.exe, both built in).
REM   - Python 3 on PATH (install from https://www.python.org/downloads/,
REM     tick "Add Python to PATH")
REM
REM Run:  double-click setup-windows.bat  OR  from cmd:  setup-windows.bat
REM
REM What this does:
REM   1. Verifies Python 3
REM   2. Downloads the Slippi Dolphin Windows build (Ishiiruka) from GitHub
REM   3. Extracts Slippi Dolphin.exe + Sys into a 'netplay\' dir
REM      (libmelee requires the SLIPPI_PATH to contain 'netplay')
REM   4. Creates a User\ dir next to the exe (libmelee's Windows home path)
REM   5. Creates the Melee ISO folder
REM   6. Creates a Python virtualenv and installs the `melee` library
REM   7. Writes env.cmd with SLIPPI_PATH / SMASH_ISO_PATH
REM
REM After running: download the Melee ISO into %USERPROFILE%\Documents\Melee\melee.iso
REM then:  call env.cmd && .venv\Scripts\python.exe arena.py
REM
REM Manual step: download the Super Smash Bros. Melee ISO and place at
REM   %USERPROFILE%\Documents\Melee\melee.iso   (or edit SMASH_ISO_PATH in env.cmd)
REM   ISO link: https://drive.google.com/file/d/1H9QNNFmVpZLys_kMJq44dpkv7EKBQqHZ/view
REM =============================================================================

setlocal enabledelayedexpansion
set "ERROR_LVL=0"

REM -----------------------------------------------------------------------------
REM Config (edit these if you want different locations)
REM -----------------------------------------------------------------------------
set "SLIPPI_VERSION=3.6.4"
set "SLIPPI_ZIP_URL=https://github.com/project-slippi/Ishiiruka/releases/download/v%SLIPPI_VERSION%/FM-Slippi-%SLIPPI_VERSION%-Win.zip"
set "INSTALL_DIR=%USERPROFILE%\slippi-dolphin\netplay"
set "DOLPHIN_HOME=%INSTALL_DIR%\User"
set "ISO_DIR=%USERPROFILE%\Documents\Melee"
set "ISO_PATH=%ISO_DIR%\melee.iso"
set "REPO_DIR=%~dp0"
if "%REPO_DIR:~-1%"=="\" set "REPO_DIR=%REPO_DIR:~0,-1%"
set "VENV_DIR=%REPO_DIR%\.venv"
set "DOLPHIN_EXE=%INSTALL_DIR%\Slippi Dolphin.exe"

echo === Smash for Sydney Windows Setup ===
echo Repo:        %REPO_DIR%
echo Venv:        %VENV_DIR%
echo Slippi dir:  %INSTALL_DIR%
echo Dolphin home:%DOLPHIN_HOME%
echo ISO:         %ISO_PATH%
echo.

REM -----------------------------------------------------------------------------
REM 1. Python 3  (find py launcher or python on PATH)
REM -----------------------------------------------------------------------------
echo [1/7] Checking Python...
set "PYTHON_EXE="
for %%c in (py python python3) do (
    if not defined PYTHON_EXE (
        where %%c >nul 2>nul && (
            for /f "delims=" %%v in ('%%c --version 2^>nul') do set "_v=%%v"
            echo !_v! | findstr /b "Python 3." >nul && set "PYTHON_EXE=%%c"
        )
    )
)
if not defined PYTHON_EXE (
    echo ERROR: Python 3 not found on PATH.
    echo   Install from https://www.python.org/downloads/
    echo   (tick "Add Python to PATH" in the installer)
    set "ERROR_LVL=1" & goto :done
)
echo       %PYTHON_EXE%  OK

REM -----------------------------------------------------------------------------
REM 2. Download + extract Slippi Dolphin (Windows zip)
REM -----------------------------------------------------------------------------
echo [2/7] Downloading + extracting Slippi Dolphin v%SLIPPI_VERSION% (Windows)...
if exist "%DOLPHIN_EXE%" (
    echo       already extracted. skipping.
) else (
    if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
    set "TMP_ZIP=%TEMP%\slippi-win.zip"
    REM curl.exe ships with Windows 10 1803+
    where curl.exe >nul 2>nul || powershell -NoProfile -Command "(New-Object System.Net.WebClient).DownloadFile('%SLIPPI_ZIP_URL%', '%TMP_ZIP%')"
    where curl.exe >nul 2>nul && curl.exe -fsSL -o "%TMP_ZIP%" "%SLIPPI_ZIP_URL%"
    if not exist "%TMP_ZIP%" (
        echo ERROR: download failed.
        set "ERROR_LVL=1" & goto :done
    )
    REM tar.exe can extract .zip on Windows 10+ : tar -xf zip -C dir
    tar -xf "%TMP_ZIP%" -C "%INSTALL_DIR%"
    if errorlevel 1 (
        REM Fallback to PowerShell Expand-Archive if tar is missing/old
        powershell -NoProfile -Command "Expand-Archive -Path '%TMP_ZIP%' -DestinationPath '%INSTALL_DIR%' -Force"
    )
    del "%TMP_ZIP%" >nul 2>nul
    echo       extracted to %INSTALL_DIR%
)

REM -----------------------------------------------------------------------------
REM 3. Verify the exe exists (libmelee expects this exact name)
REM -----------------------------------------------------------------------------
echo [3/7] Verifying Slippi Dolphin.exe...
if not exist "%DOLPHIN_EXE%" (
    echo ERROR: expected exe not found at %DOLPHIN_EXE%
    echo       Contents of %INSTALL_DIR% :
    dir "%INSTALL_DIR%" | findstr /n "." | findstr /b "[1-9]:" | more
    set "ERROR_LVL=1" & goto :done
)
echo       %DOLPHIN_EXE%  OK

REM -----------------------------------------------------------------------------
REM 4. Dolphin home (%INSTALL_DIR%\User\) - libmelee Windows home
REM -----------------------------------------------------------------------------
echo [4/7] Setting up Dolphin home (%DOLPHIN_HOME%)...
if not exist "%DOLPHIN_HOME%" mkdir "%DOLPHIN_HOME%"
REM Windows uses named pipes (\\.\pipe\slippibot{N}) - no Pipes dir needed.
echo       ready  OK

REM -----------------------------------------------------------------------------
REM 5. ISO folder
REM -----------------------------------------------------------------------------
echo [5/7] Creating ISO folder: %ISO_DIR%
if not exist "%ISO_DIR%" mkdir "%ISO_DIR%"
if exist "%ISO_PATH%" (
    echo       ISO found: %ISO_PATH%  OK
) else (
    echo       No ISO yet. Download and place at:
    echo            %ISO_PATH%
    echo            https://drive.google.com/file/d/1H9QNNFmVpZLys_kMJq44dpkv7EKBQqHZ/view
)

REM -----------------------------------------------------------------------------
REM 6. Virtualenv + melee library
REM -----------------------------------------------------------------------------
echo [6/7] Creating venv and installing melee...
if not exist "%VENV_DIR%" %PYTHON_EXE% -m venv "%VENV_DIR%"
set "VENV_PIP=%VENV_DIR%\Scripts\pip.exe"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
"%VENV_PIP%" install --upgrade pip >nul
"%VENV_PIP%" install melee
"%VENV_PY%" --version

REM -----------------------------------------------------------------------------
REM 7. env.cmd  (use 'call env.cmd' to set vars in the current shell)
REM -----------------------------------------------------------------------------
echo [7/7] Writing env.cmd...
set "ENV_FILE=%REPO_DIR%\env.cmd"
> "%ENV_FILE%" echo @echo off
>>"%ENV_FILE%" echo rem Source with:  call env.cmd
>>"%ENV_FILE%" echo rem Paths for the Smash for Sydney project (libmelee).
>>"%ENV_FILE%" echo.
>>"%ENV_FILE%" echo rem Path to the Slippi Dolphin install directory.
>>"%ENV_FILE%" echo rem libmelee expects a dir whose name contains 'netplay' (Ishiiruka build)
>>"%ENV_FILE%" echo rem and that contains 'Slippi Dolphin.exe'.
>>"%ENV_FILE%" echo set "SLIPPI_PATH=%INSTALL_DIR%"
>>"%ENV_FILE%" echo.
>>"%ENV_FILE%" echo rem Path to your Super Smash Bros. Melee ISO.
>>"%ENV_FILE%" echo set "SMASH_ISO_PATH=%ISO_PATH%"
echo       wrote %ENV_FILE%

REM -----------------------------------------------------------------------------
REM Verify libmelee can find the dolphin exe
REM -----------------------------------------------------------------------------
echo.
echo === Verifying libmelee can resolve the dolphin executable ===
set "SLIPPI_PATH=%INSTALL_DIR%"
set "VERIFY_PY=%TEMP%\smash_verify.py"
> "%VERIFY_PY%" echo import os, melee
>>"%VERIFY_PY%" echo from melee.console import get_exe_path, _is_mainline
>>"%VERIFY_PY%" echo p = os.path.expanduser(os.getenv('SLIPPI_PATH'))
>>"%VERIFY_PY%" echo print('SLIPPI_PATH:', p)
>>"%VERIFY_PY%" echo print('is_mainline:', _is_mainline(p))
>>"%VERIFY_PY%" echo exe = get_exe_path(p)
>>"%VERIFY_PY%" echo print('exe:', exe, '| exists:', os.path.isfile(exe))
"%VENV_PY%" "%VERIFY_PY%"
del "%VERIFY_PY%" >nul 2>nul

REM -----------------------------------------------------------------------------
REM Done
REM -----------------------------------------------------------------------------
echo.
echo ============================================================
echo Setup complete!
echo.
echo Next steps:
echo   1. Download the Melee ISO and place it at:
echo        %ISO_PATH%
echo      (if elsewhere, edit SMASH_ISO_PATH in env.cmd)
echo.
echo   2. Run the bots:
echo        cd /d "%REPO_DIR%"
echo        call env.cmd
echo        .venv\Scripts\python.exe arena.py
echo.
echo   Dolphin will boot, pick characters, and start the
echo   Masher vs Example fight automatically.
echo ============================================================

:done
if "%ERROR_LVL%"=="1" (
    echo.
    echo Setup FAILED. See errors above.
)
endlocal & exit /b %ERROR_LVL%