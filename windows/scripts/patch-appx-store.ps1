#Requires -Version 5.1
<#
.SYNOPSIS
  electron-builder 出力の .appx を Store 提出用に正規化・再パック・署名する。
#>
param(
    [Parameter(Mandatory = $true)][string]$InputAppx,
    [string]$OutputDir = "",
    [string]$AppxVersion = "",
    [string]$OutputAppxName = "",
    [switch]$SkipSign
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_sdk-tools.ps1"
. "$PSScriptRoot\_msstore-env.ps1"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$versionFile = Join-Path $projectRoot 'windows\version.txt'

if (-not $OutputDir) {
    $OutputDir = Join-Path $projectRoot 'dist\store'
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Load-MsStoreEnv -ProjectRoot $projectRoot

if ($AppxVersion) {
    if ($AppxVersion -notmatch '\.0$') {
        throw "Identity Version revision must be 0 (got $AppxVersion)"
    }
    $identityVersion = $AppxVersion
} else {
    $identityVersion = Get-SftpgenIdentityVersion -VersionFile $versionFile
}

Write-Host "APPX Identity Version: $identityVersion"

$makeAppx = Find-SdkTool -ToolName 'makeappx'
$work = Join-Path $projectRoot ('windows\work\patch-' + [guid]::NewGuid().ToString('N'))
$extractDir = Join-Path $work 'content'
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

try {
    Write-Host "Expand: $InputAppx"
    Expand-ArchiveLike -ArchivePath $InputAppx -Destination $extractDir

    $manifests = @(Get-ChildItem -LiteralPath $extractDir -Recurse -Filter 'AppxManifest.xml' -File)
    if ($manifests.Count -eq 0) { throw "AppxManifest.xml not found in $InputAppx" }

    foreach ($m in $manifests) {
        Set-AppxManifestVersion -ManifestPath $m.FullName -Version $identityVersion
        Set-AppxManifestDependencies -ManifestPath $m.FullName
        Set-AppxManifestAllowExternalContent -ManifestPath $m.FullName
        Inject-SteFta -ManifestPath $m.FullName
    }

    $outAppx = Join-Path $work 'patched.appx'
    Invoke-External -Exe $makeAppx -Args @('pack', '/d', $extractDir, '/p', $outAppx, '/o')

    if (-not $OutputAppxName) {
        $OutputAppxName = [System.IO.Path]::GetFileName($InputAppx)
    }
    $finalPath = Join-Path $OutputDir $OutputAppxName
    if (Test-Path -LiteralPath $finalPath) { Remove-Item -LiteralPath $finalPath -Force }
    Copy-Item -LiteralPath $outAppx -Destination $finalPath -Force

    if (-not $SkipSign) {
        $pfx = Resolve-MsStoreSigningPfx -ProjectRoot $projectRoot
        if ($pfx) { $env:MS_STORE_SIGNING_PFX = $pfx }
        Sign-StorePackage -PackagePath $finalPath
    }

    Write-Host "Store package: $finalPath"
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
