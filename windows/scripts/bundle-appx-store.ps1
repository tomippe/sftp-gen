#Requires -Version 5.1
param(
    [string[]]$InputAppxs = @(),
    [string]$OutputDir = "",
    [string]$BundleVersion = ""
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_sdk-tools.ps1"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$versionFile = Join-Path $projectRoot 'windows\version.txt'

if (-not $OutputDir) {
    $OutputDir = Join-Path $projectRoot 'windows\build\signed'
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

if ($InputAppxs.Count -eq 0) {
    $storeDir = Join-Path $projectRoot 'windows\build\store'
    $x64 = Join-Path $storeDir 'SFTPGenerator-x64.appx'
    $arm = Join-Path $storeDir 'SFTPGenerator-arm64.appx'
    if ((Test-Path $x64) -and (Test-Path $arm)) {
        $InputAppxs = @($x64, $arm)
    } else {
        throw "No input APPX. Build windows\build\store\SFTPGenerator-{x64,arm64}.appx first."
    }
}

foreach ($appx in $InputAppxs) {
    if (-not (Test-Path -LiteralPath $appx)) { throw "Input APPX not found: $appx" }
}

if (-not $BundleVersion) {
    $BundleVersion = Get-SftpgenIdentityVersion -VersionFile $versionFile
}

$makeAppx = Find-SdkTool -ToolName 'makeappx'
$bundlePath = Join-Path $OutputDir 'SFTPGenerator.appxbundle'
$bundleDir = New-SftpgenWorkDirectory -Prefix 'bundle'

try {
    New-Item -ItemType Directory -Path (Join-Path $bundleDir 'AppxMetadata') -Force | Out-Null
    foreach ($appx in $InputAppxs) {
        Copy-Item -LiteralPath $appx -Destination (Join-Path $bundleDir ([IO.Path]::GetFileName($appx))) -Force
        Write-Host "  bundle leaf: $([IO.Path]::GetFileName($appx))"
    }
    if (Test-Path -LiteralPath $bundlePath) { Remove-Item -LiteralPath $bundlePath -Force }
    Write-Host "Bundle: $bundlePath (v$BundleVersion)"
    Invoke-External -Exe $makeAppx -Args @('bundle', '/d', $bundleDir, '/p', $bundlePath, '/o', '/bv', $BundleVersion)
}
finally {
    if (Test-Path -LiteralPath $bundleDir) {
        Remove-Item -LiteralPath $bundleDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Partner Center upload bundle: $bundlePath"
