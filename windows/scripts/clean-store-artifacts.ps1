#Requires -Version 5.1
<#
.SYNOPSIS
  Store ビルドの中間成果物・旧版 APPX を削除して容量を空ける。

.PARAMETER Mode
  All         — ビルド開始時。signed / store / work / ステージング等をすべて削除。
  Intermediates — 提出用 bundle 完成後。中間 APPX・unpacked・作業ディレクトリのみ削除。
  WorkOnly    — work / LOCALAPPDATA ステージングのみ削除。
#>
param(
    [ValidateSet('All', 'Intermediates', 'WorkOnly')]
    [string]$Mode = 'All'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

function Remove-TreeSafely {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = cmd /c "rmdir /s /q `"$Path`"" 2>&1
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if (Test-Path -LiteralPath $Path) {
        Write-Warning "Could not remove (in use?): $Path"
        return $false
    }
    return $true
}

function Remove-FilesSafely {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string[]]$Filters
    )
    if (-not (Test-Path -LiteralPath $Directory)) { return }
    foreach ($filter in $Filters) {
        Get-ChildItem -LiteralPath $Directory -Filter $filter -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Clear-SftpgenWorkDirs {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $legacyWork = Join-Path $ProjectRoot 'windows\work'
    if (Test-Path -LiteralPath $legacyWork) {
        Get-ChildItem -LiteralPath $legacyWork -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-TreeSafely $legacyWork
    Remove-TreeSafely (Join-Path $env:LOCALAPPDATA 'sftpgen-work')
    Remove-TreeSafely (Join-Path $env:LOCALAPPDATA 'sftpgen-electron-build')
}

Clear-SftpgenWorkDirs -ProjectRoot $projectRoot

if ($Mode -eq 'WorkOnly') {
    Write-Host 'Cleaned work dirs (windows/work, LOCALAPPDATA\sftpgen-work, sftpgen-electron-build)'
    return
}

$winBuild = Join-Path $projectRoot 'windows\build'

Remove-TreeSafely (Join-Path $winBuild 'store')
Remove-TreeSafely (Join-Path $winBuild 'win-unpacked')
Remove-TreeSafely (Join-Path $winBuild 'win-arm64-unpacked')
Remove-FilesSafely -Directory $winBuild -Filters @('*.appx', '*.appxbundle')

if ($Mode -eq 'All') {
    Remove-TreeSafely (Join-Path $winBuild 'signed')
    $publish = Join-Path $projectRoot 'windows\build'
    foreach ($name in @('SFTPGenerator.appxbundle', 'SFTP Generator.exe', 'listingData.csv')) {
        $path = Join-Path $publish $name
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host 'Cleaned Store build artifacts (full)'
    return
}

Write-Host 'Cleaned Store intermediates (kept windows\build\signed\SFTPGenerator.appxbundle)'
