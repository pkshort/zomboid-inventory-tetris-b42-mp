@echo off
setlocal

REM === Steam Workshop Upload Script ===
REM Usage: upload-workshop.bat YOUR_STEAM_USERNAME

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"
set "STEAMCMD_DIR=%SCRIPT_DIR%steamcmd"
set "STEAMCMD=%STEAMCMD_DIR%\steamcmd.exe"
set "WORKSHOP_DIR=%USERPROFILE%\Zomboid\Workshop\InventoryTetris"
set "MOD_DIR=%SCRIPT_DIR%Contents\mods\InventoryTetris"
set "CONTENTFOLDER=%SCRIPT_DIR%Contents"

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

REM --- Prompt for change description (optional override; default = git auto-generate) ---
echo.
echo Enter a change description for Steam Workshop, or press Enter to auto-generate from git:
set /p CHANGENOTE=">> "

REM --- Build runtime VDF: copy committed vdf to %TEMP% and substitute <CONTENTFOLDER>. ---
REM Keeps the committed vdf free of the local absolute path (which contains the
REM Windows account name) and avoids the changenote-leakage of editing it in place.
set "BAT_FILE=%~f0"
set "VDF_PATH=%TEMP%\workshop_upload_run.vdf"
copy /Y "%SCRIPT_DIR%workshop_upload.vdf" "%VDF_PATH%" >nul
powershell -ExecutionPolicy Bypass -NoProfile -Command "$c=Get-Content -LiteralPath $env:VDF_PATH -Raw; $c=$c.Replace('<CONTENTFOLDER>', $env:CONTENTFOLDER); Set-Content -LiteralPath $env:VDF_PATH -Value $c -NoNewline"

REM --- Update changenote in temp VDF (auto-generates if CHANGENOTE is empty) ---
REM Args are passed via env vars so cmd quoting doesn't mangle them.
powershell -ExecutionPolicy Bypass -NoProfile -Command "$c=Get-Content -LiteralPath $env:BAT_FILE -Raw; $m='::'+'PS_BLOCK_START'+'::'; $i=$c.IndexOf($m); if($i -lt 0){throw 'sentinel missing'}; $sb=[scriptblock]::Create($c.Substring($i+$m.Length)); & $sb -Vdf $env:VDF_PATH -Override $env:CHANGENOTE"
if errorlevel 1 (
    echo Failed to set change description. Aborting.
    exit /b 1
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
"%STEAMCMD%" +login %1 +workshop_build_item "%VDF_PATH%" +quit

del "%VDF_PATH%" 2>nul

echo.
echo Done! Check output above for success/failure.
pause
goto :eof

::PS_BLOCK_START::
param(
    [Parameter(Mandatory=$true)] [string]$Vdf,
    [string]$Override = ''
)

# PS 5.1 wraps native stderr into ErrorRecord, which would terminate under 'Stop'.
# Native git warnings (e.g. CRLF normalization) are not failures for our purposes.
$ErrorActionPreference = 'Continue'

function Get-AutoNotes {
    $modRoot = 'Contents/mods/InventoryTetris'

    # Discover version folders on disk and find ones that are entirely untracked
    # (= newly added this release). Edits within version folders are duplicated
    # across all of them, so we'll dedupe by basename later.
    $versionFolders = @(Get-ChildItem $modRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $newVersionFolders = @()
    foreach ($v in $versionFolders) {
        $folder = "$modRoot/$v"
        $trackedInFolder = & git ls-files $folder
        if (-not $trackedInFolder) {
            $newVersionFolders += $v
        }
    }

    # The release boundary is the most recent commit that bumped any tracked mod.info.
    $modInfos = $versionFolders |
        Where-Object { $newVersionFolders -notcontains $_ } |
        ForEach-Object { "$modRoot/$_/mod.info" }

    $items = @()

    # Source 1: commit subjects since the last mod.info bump (workflow: commit before upload).
    if ($modInfos) {
        $lastBump = (& git log -1 --format=%H -- @modInfos | Out-String).Trim()
        if ($lastBump) {
            $subjects = & git log "$lastBump..HEAD" --pretty=format:%s
            if ($subjects) {
                $items += @($subjects) |
                    Where-Object { $_ -and $_ -notmatch '^(chore: )?bump version' -and $_ -notmatch '^release ' } |
                    ForEach-Object {
                        ($_ -replace '^(fix|feat|chore|refactor|docs|test|perf|ci|build|style)(\([^)]*\))?:\s*', '').Trim()
                    }
            }
        }
    }

    # Source 2: file-level summary of uncommitted changes (workflow: upload, then commit).
    $tracked = & git diff --name-only HEAD
    $untracked = & git ls-files --others --exclude-standard

    $newFolderRegex = if ($newVersionFolders) {
        '^' + [regex]::Escape($modRoot) + '/(' + (($newVersionFolders | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')/'
    } else { $null }

    $changed = @(@($tracked) + @($untracked)) |
        Where-Object {
            $_ -and `
            $_ -match '^Contents/' -and `
            $_ -notmatch 'mod\.info$' -and `
            ($newFolderRegex -eq $null -or $_ -notmatch $newFolderRegex)
        }

    # Dedupe by basename so the same edit replicated across version folders shows once.
    if ($changed) {
        $names = $changed | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object -Unique
        $summary = if ($names.Count -le 10) {
            ($names -join ', ')
        } else {
            (($names | Select-Object -First 9) -join ', ') + ", and $($names.Count - 9) more"
        }
        $items += "Update $summary"
    }

    foreach ($v in ($newVersionFolders | Sort-Object)) {
        $items += "Add B$v support"
    }

    return ($items -join '; ')
}

if ($Override) {
    $note = $Override
} else {
    $note = Get-AutoNotes
}

if (-not $note) {
    Write-Error 'No change notes available (override empty and no commits or uncommitted changes since last mod.info bump).'
    exit 1
}

# VDF strings cannot contain literal double quotes; replace with single quotes.
$noteForVdf = $note -replace '"', "'"

$content = Get-Content $Vdf -Raw
$match = [regex]::Match($content, '"changenote"\s+"[^"]*"')
if (-not $match.Success) {
    Write-Error 'Could not locate "changenote" line in VDF.'
    exit 1
}
$old = $match.Value
$new = '"changenote"   "' + $noteForVdf + '"'
$content = $content.Replace($old, $new)
Set-Content -Path $Vdf -Value $content -NoNewline

Write-Host "Change notes set to:"
Write-Host "  $note"
