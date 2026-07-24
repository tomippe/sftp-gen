#Requires -Version 5.1
<#
  windows/resources/icon.png から electron-builder APPX 用タイルを生成する。
  Mac 用 mac/ フォルダは触らない。
#>
param(
    [string]$SourcePng = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

if (-not $SourcePng) {
    $SourcePng = Join-Path $projectRoot 'windows\resources\icon.png'
}
if (-not (Test-Path -LiteralPath $SourcePng)) {
    throw "Icon not found: $SourcePng"
}
if (-not $OutDir) {
    $OutDir = Join-Path $projectRoot 'windows\resources'
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Add-Type -AssemblyName System.Drawing

function Save-ScaledPng {
    param(
        [System.Drawing.Image]$Source,
        [int]$Width,
        [int]$Height,
        [string]$DestPath,
        [System.Drawing.Color]$Background = [System.Drawing.Color]::Transparent
    )
    $bmp = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    if ($Background -ne [System.Drawing.Color]::Transparent) {
        $g.Clear($Background)
    } else {
        $g.Clear([System.Drawing.Color]::Transparent)
    }
    $scale = [Math]::Min($Width / $Source.Width, $Height / $Source.Height)
    $w = [int]($Source.Width * $scale)
    $h = [int]($Source.Height * $scale)
    $x = ($Width - $w) / 2
    $y = ($Height - $h) / 2
    $g.DrawImage($Source, $x, $y, $w, $h)
    $g.Dispose()
    $bmp.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$img = [System.Drawing.Image]::FromFile($SourcePng)
try {
    Save-ScaledPng -Source $img -Width 50 -Height 50 -DestPath (Join-Path $OutDir 'StoreLogo.png')
    Save-ScaledPng -Source $img -Width 150 -Height 150 -DestPath (Join-Path $OutDir 'Square150x150Logo.png')
    Save-ScaledPng -Source $img -Width 44 -Height 44 -DestPath (Join-Path $OutDir 'Square44x44Logo.png')
    Save-ScaledPng -Source $img -Width 310 -Height 150 -DestPath (Join-Path $OutDir 'Wide310x150Logo.png') -Background ([System.Drawing.Color]::White)
    Write-Host "APPX icons -> $OutDir"
}
finally {
    $img.Dispose()
}
