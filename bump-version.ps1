$modDir = Join-Path $PSScriptRoot "Contents\mods\InventoryTetris"
$files = @(
    Join-Path $modDir "42.17\mod.info"
    Join-Path $modDir "42.16\mod.info"
    Join-Path $modDir "42.15\mod.info"
    Join-Path $modDir "42.13\mod.info"
    Join-Path $modDir "42\mod.info"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $content = Get-Content $f
        $content = $content | ForEach-Object {
            if ($_ -match '^modversion=(\d+)\.(\d+)\.(\d+)') {
                $patch = [int]$Matches[3] + 1
                "modversion=$($Matches[1]).$($Matches[2]).$patch"
            } else {
                $_
            }
        }
        $content | Set-Content $f
        Write-Host "  Updated $f"
    }
}

$verLine = Select-String -Path (Join-Path $modDir "42.17\mod.info") -Pattern "^modversion="
Write-Host "New version: $($verLine.Line.Split('=')[1])"
