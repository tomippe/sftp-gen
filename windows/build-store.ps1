#Requires -Version 5.1
<#
.SYNOPSIS
  SFTP Generator — Microsoft Store 用 APPX / APPX bundle ビルド

.EXAMPLE
  .\windows\build-store.ps1           # MSIX bundle（署名済み）
  .\windows\build-store.ps1 -AppOnly  # electron-builder の .appx のみ（署名・bundle 省略）
#>
param(
    [switch]$AppOnly,
    [switch]$Noverup
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$rootDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$scriptsDir = Join-Path $PSScriptRoot 'scripts'
$versionFile = Join-Path $PSScriptRoot 'version.txt'

. (Join-Path $rootDir '..\build-common\helpers.ps1')
. (Join-Path $rootDir '..\build-common\version.ps1')
. (Join-Path $scriptsDir '_msstore-env.ps1')

Write-Step 'Version'
$version = Read-AppVersion -VersionFile $versionFile
Write-Ok "v$version"

$pkgJsonPath = Join-Path $rootDir 'package.json'
$pkgJson = Get-Content $pkgJsonPath -Raw
$pkgJson = $pkgJson -replace '"version":\s*"[^"]*"', "`"version`": `"$version`""
Set-Content -Path $pkgJsonPath -Value $pkgJson -NoNewline

Write-Step 'APPX icons'
& (Join-Path $scriptsDir 'generate-appx-icons.ps1')
if (-not $?) { throw 'generate-appx-icons.ps1 failed' }

Write-Step 'Clean & Install'
$distPath = Join-Path $rootDir 'dist'
foreach ($sub in @('win-unpacked', 'store', 'signed', '*.appx', '*.appxbundle')) {
    Get-ChildItem -Path $distPath -Filter $sub -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -Path $distPath -Filter '*.appx' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $distPath -Filter '*.appxbundle' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
foreach ($d in @('out', '.webpack')) {
    $p = Join-Path $rootDir $d
    if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue }
}
Push-Location $rootDir
cmd /c "npm install --force >nul 2>nul"
Pop-Location
Write-Ok '依存関係 OK'

$archs = @('x64', 'arm64')
$patched = @()

foreach ($cpuArch in $archs) {
    Write-Step "electron-builder appx ($cpuArch)"
    & (Join-Path $scriptsDir 'electron-builder-local.ps1') -ProjectDir $rootDir -Arch $cpuArch
    if (-not $?) { throw "electron-builder failed ($cpuArch)" }

    $rawAppx = Get-ChildItem -LiteralPath (Join-Path $rootDir 'dist') -Filter '*.appx' -File |
        Where-Object { $_.Name -match "-$cpuArch\.appx$" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $rawAppx) {
        $rawAppx = Get-ChildItem -LiteralPath (Join-Path $rootDir 'dist') -Filter '*.appx' -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }
    if (-not $rawAppx) { throw "No .appx in dist ($cpuArch)" }

    Write-Step "Patch & sign ($cpuArch)"
    $leaf = "SFTPGenerator-$cpuArch.appx"
    & (Join-Path $scriptsDir 'patch-appx-store.ps1') `
        -InputAppx $rawAppx.FullName `
        -OutputAppxName $leaf
    if (-not $?) { throw "patch-appx-store.ps1 failed ($cpuArch)" }
    $patched += Join-Path $rootDir "dist\store\$leaf"
}

if ($AppOnly) {
    Write-Step "Build complete (AppOnly) v$version"
    exit 0
}

Write-Step 'Bundle'
& (Join-Path $scriptsDir 'bundle-appx-store.ps1') -InputAppxs $patched
if (-not $?) { throw 'bundle-appx-store.ps1 failed' }

$bundlePath = Join-Path $rootDir 'dist\signed\SFTPGenerator.appxbundle'
$pfx = Resolve-MsStoreSigningPfx -ProjectRoot $rootDir
if ($pfx) { $env:MS_STORE_SIGNING_PFX = $pfx }
Sign-StorePackage -PackagePath $bundlePath

Write-Step 'Listing CSV'
$listingScript = Join-Path $scriptsDir 'generate-listing-csv.py'
$outCsv = Join-Path $rootDir 'dist\listingData.csv'
if (Test-Path $listingScript) {
    $metaPath = Join-Path $rootDir 'docs\store-metadata.md'
    $templatePath = Join-Path $scriptsDir 'listing-csv-template.csv'
    if ($env:MS_STORE_PRODUCT_ID) {
        $outCsv = Join-Path $rootDir "dist\listingData-$($env:MS_STORE_PRODUCT_ID).csv"
    }
    python $listingScript --metadata $metaPath --template $templatePath -o $outCsv
    if ($LASTEXITCODE -eq 0) { Write-Ok $outCsv }
}

if (-not $Noverup) {
    Write-Step 'Version Update'
    Save-NextAppVersion -Version $version -VersionFile $versionFile
}

Write-Step "Store build complete v$version"
$publishDir = Join-Path $PSScriptRoot 'publish'
New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
Copy-Item -LiteralPath $bundlePath -Destination (Join-Path $publishDir 'SFTPGenerator.appxbundle') -Force
if (Test-Path $outCsv) { Copy-Item -LiteralPath $outCsv -Destination (Join-Path $publishDir 'listingData.csv') -Force }
Write-Host ''
Write-Host "  Partner Center upload:" -ForegroundColor Gray
Write-Host "  $bundlePath" -ForegroundColor White
Write-Host "  (copy) $publishDir\SFTPGenerator.appxbundle" -ForegroundColor Gray
$exePath = Join-Path $rootDir 'dist\win-unpacked\SFTP Generator.exe'
if (Test-Path -LiteralPath $exePath) {
    Copy-Item -LiteralPath $exePath -Destination (Join-Path $publishDir 'SFTP Generator.exe') -Force
    Write-Host "  EXE (x64 unpacked): $exePath" -ForegroundColor Gray
    Write-Host "  (copy) $publishDir\SFTP Generator.exe" -ForegroundColor Gray
}
Write-Host '  Listing: docs/store-metadata.md , windows/publish/listingData.csv' -ForegroundColor Gray
Write-Host ''
