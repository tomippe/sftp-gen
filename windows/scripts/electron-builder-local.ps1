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
if (Test-Path -LiteralPath $localRoot) {
    $localRoot = Join-Path $env:LOCALAPPDATA ('sftpgen-electron-build-' + [guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $localRoot -Force | Out-Null

robocopy $ProjectDir $localRoot /E /XD windows\build mac\build node_modules windows\work .git /R:1 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 16) { throw "robocopy project -> local failed ($LASTEXITCODE)" }

$nodeModules = Join-Path $ProjectDir 'node_modules'
if (Test-Path -LiteralPath $nodeModules) {
    robocopy $nodeModules (Join-Path $localRoot 'node_modules') /E /R:1 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    if ($LASTEXITCODE -ge 16) { throw "robocopy node_modules failed ($LASTEXITCODE)" }
}

Push-Location $localRoot
try {
    npm run $npmScript
    if ($LASTEXITCODE -ne 0) { throw "electron-builder failed" }
} finally { Pop-Location }

$artifactSrc = Join-Path $localRoot 'windows\build'
if (-not (Test-Path -LiteralPath $artifactSrc)) { throw "local windows/build not produced" }

$artifactDest = Join-Path $ProjectDir 'windows\build'
New-Item -ItemType Directory -Path $artifactDest -Force | Out-Null
robocopy $artifactSrc $artifactDest /E /R:1 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 16) {
    Write-Warning "robocopy build -> project failed; artifacts at $artifactSrc"
} else {
    Write-Host "  build copied back to $artifactDest"
}
Remove-Item -LiteralPath $localRoot -Recurse -Force -ErrorAction SilentlyContinue
