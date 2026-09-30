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

if ($env:TOMIPPE_BUILD_COMMON_ROOT -and (Test-Path -LiteralPath (Join-Path $env:TOMIPPE_BUILD_COMMON_ROOT 'windows-build-bootstrap.ps1'))) {
    . (Join-Path $env:TOMIPPE_BUILD_COMMON_ROOT 'windows-build-bootstrap.ps1')
} else {
    . (Join-Path $PSScriptRoot '..\..\build-common\windows-build-bootstrap.ps1')
}
$buildCommonRoot = Resolve-BuildCommonRoot -WindowsScriptRoot $PSScriptRoot
. (Join-Path $buildCommonRoot 'windows-unc-build.ps1')
if ($env:TOMIPPE_WIN_BUILD_STAGED -ne '1') {
    $projRootForStage = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    if (Invoke-WindowsBuildViaLocalStageIfNeeded `
            -ProjectRoot $projRootForStage `
            -StageName 'sftp-gen-win-build' `
            -ArtifactRelativePaths @('windows\build', 'windows\version.txt') `
            -BuildScriptRelative 'windows\build-store.ps1' `
            -BoundParameters $PSBoundParameters) {
        # Yoink はドロップしたファイルをパス参照で保持するため、ステージ（%LOCALAPPDATA%）の
        # 成果物を送るとビルド終了時のステージ削除で参照が切れる。コピーバック後の
        # プロジェクト側（Mac 共有）のパスを送る
        $signedDir = Join-Path $projRootForStage 'windows\build\signed'
        if (Test-Path -LiteralPath $signedDir) {
            $yoinkFiles = @(Get-ChildItem -LiteralPath $signedDir -File |
                Where-Object { $_.Extension -in @('.appxbundle', '.msixbundle', '.csv', '.png') } |
                ForEach-Object { $_.FullName })
            if ($yoinkFiles.Count -gt 0) {
                & (Join-Path $buildCommonRoot 'send-mspc-artifacts-to-yoink.ps1') -ArtifactPath $yoinkFiles
                if ($LASTEXITCODE -ne 0) { Write-Host 'WARN: Yoink send failed (artifacts remain on disk)' -ForegroundColor Yellow }
            }
        }
        exit 0
    }
}

$rootDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$scriptsDir = Join-Path $PSScriptRoot 'scripts'
$versionFile = Join-Path $PSScriptRoot 'version.txt'

. (Join-Path $buildCommonRoot 'helpers.ps1')
. (Join-Path $buildCommonRoot 'version.ps1')
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
& (Join-Path $scriptsDir 'clean-store-artifacts.ps1') -Mode All
if (-not $?) { throw 'clean-store-artifacts.ps1 failed' }
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
    Get-ChildItem -LiteralPath (Join-Path $rootDir 'windows\build') -Filter '*.appx' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    & (Join-Path $scriptsDir 'electron-builder-local.ps1') -ProjectDir $rootDir -Arch $cpuArch
    if (-not $?) { throw "electron-builder failed ($cpuArch)" }

    $rawCandidates = @(Get-ChildItem -LiteralPath (Join-Path $rootDir 'windows\build') -Filter '*.appx' -File)
    if ($rawCandidates.Count -eq 0) { throw "No .appx in windows/build ($cpuArch)" }
    $rawAppx = if ($cpuArch -eq 'arm64') {
        $rawCandidates | Where-Object { $_.Name -match 'arm64\.appx$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    } else {
        $rawCandidates | Where-Object { $_.Name -notmatch 'arm64\.appx$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if (-not $rawAppx) { throw "No .appx in windows/build ($cpuArch)" }

    Write-Step "Patch & sign ($cpuArch)"
    $leaf = "SFTPGenerator-$cpuArch.appx"
    & (Join-Path $scriptsDir 'patch-appx-store.ps1') `
        -InputAppx $rawAppx.FullName `
        -OutputAppxName $leaf
    if (-not $?) { throw "patch-appx-store.ps1 failed ($cpuArch)" }
    $patched += Join-Path $rootDir "windows\build\store\$leaf"
}

if ($AppOnly) {
    Write-Step 'Trim work dirs'
    & (Join-Path $scriptsDir 'clean-store-artifacts.ps1') -Mode WorkOnly
    if (-not $?) { throw 'clean-store-artifacts.ps1 failed' }
    Write-Step "Build complete (AppOnly) v$version"
    exit 0
}

Write-Step 'Bundle'
& (Join-Path $scriptsDir 'bundle-appx-store.ps1') -InputAppxs $patched
if (-not $?) { throw 'bundle-appx-store.ps1 failed' }

$bundlePath = Join-Path $rootDir 'windows\build\signed\SFTPGenerator.appxbundle'
$pfx = Resolve-MsStoreSigningPfx -ProjectRoot $rootDir
if ($pfx) { $env:MS_STORE_SIGNING_PFX = $pfx }
Sign-StorePackage -PackagePath $bundlePath

Write-Step 'Listing CSV'
$listingScript = Join-Path $scriptsDir 'generate-listing-csv.py'
$outCsv = Join-Path $rootDir 'windows\build\signed\listingData.csv'
if (Test-Path $listingScript) {
    $metaPath = Join-Path $rootDir 'docs\store-metadata.md'
    $templatePath = Join-Path $scriptsDir 'listing-csv-template.csv'
    if ($env:MS_STORE_PRODUCT_ID) {
        $outCsv = Join-Path $rootDir "windows\build\signed\listingData-$($env:MS_STORE_PRODUCT_ID).csv"
    }
    python $listingScript --metadata $metaPath --template $templatePath -o $outCsv
    if ($LASTEXITCODE -ne 0) { throw 'generate-listing-csv.py failed' }
    Write-Ok $outCsv
}

# CSV が相対パスで参照する掲載画像（スクショ・ロゴ）を CSV と同じフォルダに置く
# （Partner Center のインポートは CSV と画像をまとめて受け取る）
$listingAssetsDir = Join-Path $rootDir 'windows\resources\listing'
$listingAssets = @()
if (Test-Path -LiteralPath $listingAssetsDir) {
    foreach ($img in Get-ChildItem -LiteralPath $listingAssetsDir -Filter '*.png' -File) {
        $dest = Join-Path (Split-Path -Parent $outCsv) $img.Name
        Copy-Item -LiteralPath $img.FullName -Destination $dest -Force
        $listingAssets += $dest
    }
    Write-Ok "Listing images: $($listingAssets.Count) file(s)"
}

Write-Step 'Yoink (Partner Center submit artifacts)'
if ($env:TOMIPPE_WIN_BUILD_STAGED -eq '1') {
    # ステージ実行中。成果物をコピーバックした後、呼び出し元がプロジェクト側のパスを送る
    Write-Ok 'ステージ実行のため送信はコピーバック後に行う'
} else {
    $sendYoink = Join-Path $buildCommonRoot 'send-mspc-artifacts-to-yoink.ps1'
    $yoinkArtifacts = @()
    if ($bundlePath -and (Test-Path -LiteralPath $bundlePath)) { $yoinkArtifacts += $bundlePath }
    if ($outCsv -and (Test-Path -LiteralPath $outCsv)) { $yoinkArtifacts += $outCsv }
    $yoinkArtifacts += @($listingAssets | Where-Object { Test-Path -LiteralPath $_ })
    if ($yoinkArtifacts.Count -gt 0) {
        & $sendYoink -ArtifactPath $yoinkArtifacts
        if ($LASTEXITCODE -ne 0) { Write-Warn 'Yoink send failed (artifacts remain on disk)' }
    }
}

if (-not $Noverup) {
    Write-Step 'Version Update'
    Save-NextAppVersion -Version $version -VersionFile $versionFile
}

Write-Step 'Trim intermediates'
& (Join-Path $scriptsDir 'clean-store-artifacts.ps1') -Mode Intermediates
if (-not $?) { throw 'clean-store-artifacts.ps1 failed' }

Write-Step "Store build complete v$version"
Write-Host ''
Write-Host "  Partner Center upload:" -ForegroundColor Gray
Write-Host "  $bundlePath" -ForegroundColor White
if (Test-Path $outCsv) {
    Write-Host "  Listing CSV: $outCsv" -ForegroundColor Gray
}
Write-Host '  Listing text: docs/store-metadata.md' -ForegroundColor Gray
Write-Host ''
