@echo off
setlocal

REM === Steam Workshop Upload Script ===
REM Usage: upload-workshop.bat YOUR_STEAM_USERNAME

set SCRIPT_DIR=%~dp0
set STEAMCMD_DIR=%SCRIPT_DIR%steamcmd
set STEAMCMD=%STEAMCMD_DIR%\steamcmd.exe
set WORKSHOP_DIR=C:\Users\pkevi\Zomboid\Workshop\InventoryTetris
set MOD_DIR=%SCRIPT_DIR%Contents\mods\InventoryTetris

if "%~1"=="" (
    echo Usage: upload-workshop.bat YOUR_STEAM_USERNAME
    exit /b 1
)

REM --- Install SteamCMD if missing ---
if not exist "%STEAMCMD%" (
    echo SteamCMD not found, downloading...
    mkdir "%STEAMCMD_DIR%" 2>nul
    powershell -Command "Invoke-WebRequest -Uri 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile '%STEAMCMD_DIR%\steamcmd.zip'"
    powershell -Command "Expand-Archive -Path '%STEAMCMD_DIR%\steamcmd.zip' -DestinationPath '%STEAMCMD_DIR%' -Force"
    del "%STEAMCMD_DIR%\steamcmd.zip"
    echo SteamCMD installed.
)

REM --- Auto-increment patch version ---
echo Incrementing mod version...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%bump-version.ps1"

REM --- Sync to Workshop directory ---
echo Syncing to Workshop directory...
robocopy "%MOD_DIR%" "%WORKSHOP_DIR%" /MIR /NJH /NJS /NDL /NP >nul
echo Synced.

REM --- Upload to Steam Workshop ---
echo Uploading to Steam Workshop...
"%STEAMCMD%" +login %1 +workshop_build_item "%SCRIPT_DIR%workshop_upload.vdf" +quit

echo.
echo Done! Check output above for success/failure.
pause
