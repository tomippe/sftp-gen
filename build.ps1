#Requires -Version 5.1
<#
.SYNOPSIS
    SFTP Gen Windows Build Script (Electron, no MSIX)
    Reads version from version.txt, builds EXE, creates _win.zip, copies to apps.tomippe.jp, uploads via FTP.

.EXAMPLE
    .\build.ps1              # Full build (EXE + zip + upload)
    .\build.ps1 -Exe         # Build EXE only (skip zip/copy/upload)
#>
param(
    [switch]$Exe
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$rootDir = $PSScriptRoot

# 共通スクリプト読み込み
. "$rootDir\..\build-common\helpers.ps1"
. "$rootDir\..\build-common\version.ps1"
. "$rootDir\..\build-common\ftp-upload.ps1"

$APP_NAME = "sftp-gen"
$ZIP_NAME = "${APP_NAME}_win.zip"
$DIST_DIR = Join-Path $rootDir "..\apps.tomippe.jp\sftp-gen"

# ─── Version ───

Write-Step "Version"

$version = Read-AppVersion
Write-Ok "v$version"

# Update package.json if it exists
$pkgJsonPath = Join-Path $rootDir "package.json"
if (Test-Path $pkgJsonPath) {
    $pkgJson = Get-Content $pkgJsonPath -Raw
    $pkgJson = $pkgJson -replace '"version":\s*"[^"]*"', "`"version`": `"$version`""
    Set-Content -Path $pkgJsonPath -Value $pkgJson -NoNewline
    Write-Ok "package.json を v$version に更新しました"
}

# ─── Clean & Install ───

Write-Step "Clean & Install"

$cleanDirs = @("dist", "out", ".webpack")
foreach ($d in $cleanDirs) {
    $p = Join-Path $rootDir $d
    if (Test-Path $p) { Remove-Item -Recurse -Force $p }
}
Write-Ok "クリーンアップ完了"

Write-Host "  npm install ..." -ForegroundColor Gray
Push-Location $rootDir
npm install --force 2>&1 | Out-Null
Pop-Location
Write-Ok "依存関係インストール完了"

# ─── Build Windows ───

Write-Step "Building Windows (x64)"

Push-Location $rootDir
npm run build -- --win --x64
if ($LASTEXITCODE -ne 0) { Write-Error "Windows build failed"; exit 1 }
Pop-Location
Write-Ok "Windows ビルド完了"

# -Exe mode: skip zip/copy/upload
if ($Exe) {
    Write-Step "Build Complete - v$version (-Exe mode)"
    Write-Host "  EXE: dist\win-unpacked\" -ForegroundColor Gray
    exit 0
}

# ─── Create _win.zip ───

Write-Step "Creating $ZIP_NAME"

$winUnpacked = Join-Path $rootDir "dist\win-unpacked"
if (-not (Test-Path $winUnpacked)) {
    Write-Error "dist\win-unpacked が見つかりません"
    exit 1
}

$zipPath = Join-Path $rootDir "dist\$ZIP_NAME"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Compress-Archive -Path "$winUnpacked\*" -DestinationPath $zipPath -CompressionLevel Optimal
$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Ok "$ZIP_NAME ($zipSize MB)"

# ─── Copy to apps.tomippe.jp ───

Write-Step "Copying to apps.tomippe.jp"

if (-not (Test-Path $DIST_DIR)) {
    New-Item -ItemType Directory -Path $DIST_DIR -Force | Out-Null
}

$distZipPath = Join-Path $DIST_DIR $ZIP_NAME
Copy-Item $zipPath $distZipPath -Force
Write-Ok "$distZipPath にコピーしました"

# ─── FTP Upload ───

Write-Step "FTP Upload"
Send-FtpFile -LocalFile $distZipPath -RemotePath "sftp-gen/$ZIP_NAME"

# ─── Save Next Version ───

Write-Step "Version Update"
Save-NextAppVersion -Version $version

# ─── Summary ───

Write-Step "Build Complete - v$version"
Write-Host ""
Write-Host "  EXE: dist\win-unpacked\" -ForegroundColor Gray
Write-Host "  ZIP: $distZipPath" -ForegroundColor Gray
Write-Host ""
