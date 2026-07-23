#Requires -Version 5.1
<#
  UNC / ネットワークドライブ (Y: 等) 上では electron-builder をローカルで実行する。
#>
param(
    [Parameter(Mandatory = $true)][string]$ProjectDir,
    [ValidateSet('x64', 'arm64')][string]$Arch = 'x64'
)

$ErrorActionPreference = 'Stop'

function Test-UncPath([string]$Path) {
    $root = [System.IO.Path]::GetPathRoot($Path)
    if ($root -match '^\\\\') { return $true }
    try {
        $drive = Get-PSDrive -Name ($root.TrimEnd('\').TrimEnd(':')) -ErrorAction SilentlyContinue
        return ($drive -and $drive.DisplayRoot -like '\\*')
    } catch { return $false }
}

$localRoot = Join-Path $env:LOCALAPPDATA 'sftpgen-electron-build'
$npmScript = "build:store:$Arch"
$isUnc = Test-UncPath $ProjectDir

if (-not $isUnc) {
    Write-Host "electron-builder appx ($Arch, local path)..."
    Push-Location $ProjectDir
    try {
        npm run $npmScript
        if ($LASTEXITCODE -ne 0) { throw "electron-builder failed" }
    } finally { Pop-Location }
    exit 0
}

Write-Host "electron-builder appx ($Arch via local staging)..."
Write-Host "  from: $ProjectDir"
Write-Host "  stage: $localRoot"

Remove-Item -LiteralPath $localRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $localRoot -Force | Out-Null

robocopy $ProjectDir $localRoot /MIR /XD dist node_modules windows\work /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy project -> local failed ($LASTEXITCODE)" }

$nodeModules = Join-Path $ProjectDir 'node_modules'
if (Test-Path -LiteralPath $nodeModules) {
    robocopy $nodeModules (Join-Path $localRoot 'node_modules') /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy node_modules failed" }
}

Push-Location $localRoot
try {
    npm run $npmScript
    if ($LASTEXITCODE -ne 0) { throw "electron-builder failed" }
} finally { Pop-Location }

$distSrc = Join-Path $localRoot 'dist'
if (-not (Test-Path -LiteralPath $distSrc)) { throw "local dist/ not produced" }

$distDest = Join-Path $ProjectDir 'dist'
New-Item -ItemType Directory -Path $distDest -Force | Out-Null
robocopy $distSrc $distDest /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Warning "robocopy dist -> project failed; artifacts at $distSrc"
} else {
    Write-Host "  dist copied back to $distDest"
}
