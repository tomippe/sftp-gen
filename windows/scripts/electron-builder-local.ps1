#Requires -Version 5.1
<#
  sftp-gen — build-common/electron-builder-local.ps1 ラッパー
#>
param(
    [Parameter(Mandatory = $true)][string]$ProjectDir,
    [ValidateSet('x64', 'arm64')][string]$Arch = 'x64'
)

$ErrorActionPreference = 'Stop'
$buildCommon = $env:TOMIPPE_BUILD_COMMON_ROOT
if (-not $buildCommon -or -not (Test-Path -LiteralPath (Join-Path $buildCommon 'electron-builder-local.ps1'))) {
    $buildCommon = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\build-common')).Path
}

& (Join-Path $buildCommon 'electron-builder-local.ps1') `
    -ProjectDir $ProjectDir `
    -StageName 'sftpgen-win-electron-build' `
    -NpmScript "build:store:$Arch" `
    -OutputRelative 'windows/build'
