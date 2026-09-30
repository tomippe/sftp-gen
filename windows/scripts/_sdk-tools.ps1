#Requires -Version 5.1

function New-SftpgenWorkDirectory {
    param([Parameter(Mandatory = $true)][string]$Prefix)
    $root = Join-Path $env:LOCALAPPDATA 'sftpgen-work'
    $dir = Join-Path $root ($Prefix + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Find-SdkTool {
    param([Parameter(Mandatory = $true)][string]$ToolName)

    $candidates = @()
    foreach ($root in @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "${env:ProgramFiles}\Windows Kits\10\bin")) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $candidates += Get-ChildItem -LiteralPath $root -Recurse -Filter "$ToolName.exe" -ErrorAction SilentlyContinue
    }
    if ($candidates.Count -eq 0) {
        throw "Could not find $ToolName.exe. Install Windows 10/11 SDK."
    }
    return ($candidates | Sort-Object {
            $ver = $null
            [void][version]::TryParse($_.Directory.Name, [ref]$ver)
            if ($ver) { $ver } else { [version]'0.0.0.0' }
        } -Descending | Select-Object -First 1).FullName
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Args
    )
    $argLine = ($Args | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
        }) -join ' '
    Write-Host "> $Exe $argLine"
    & $Exe @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Exe $argLine"
    }
}

function Expand-ArchiveLike {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $ext = [System.IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()
    if ($ext -in '.appx', '.msix', '.appxbundle', '.msixbundle') {
        $makeAppx = Find-SdkTool -ToolName 'makeappx'
        Invoke-External -Exe $makeAppx -Args @('unpack', '/p', $ArchivePath, '/d', $Destination, '/o')
        return
    }
    if ($ext -eq '.zip') {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
        return
    }
    $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) ("sftpgen-expand-" + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        Copy-Item -LiteralPath $ArchivePath -Destination $tempZip -Force
        Expand-Archive -LiteralPath $tempZip -DestinationPath $Destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force }
    }
}

function Assert-AppxCustomTileAssets {
    <#
      electron-builder は buildResources/appx/ が無い（または空）だと黙って
      ベンダーのサンプルタイル（winCodeSign/appxAssets/SampleAppx.*.png）を同梱する。
      そのまま提出すると Store 認証 10.1.1.11「On Device Tiles（既定画像）」で不合格になる
      ため、展開済み APPX のタイルが自前アセットと一致することをハッシュで検証する。
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ExtractedAppxDir,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )
    $required = @('StoreLogo.png', 'Square44x44Logo.png', 'Square150x150Logo.png', 'Wide310x150Logo.png')
    $customDir = Join-Path $ProjectRoot 'windows\resources\appx'
    foreach ($name in $required) {
        $expected = Join-Path $customDir $name
        if (-not (Test-Path -LiteralPath $expected)) {
            throw "Custom tile asset missing: $expected (run generate-appx-icons.ps1)"
        }
        $actual = Join-Path (Join-Path $ExtractedAppxDir 'assets') $name
        if (-not (Test-Path -LiteralPath $actual)) {
            throw "APPX asset missing after pack: assets\$name — electron-builder が windows\resources\appx を拾えていません"
        }
        $expectedHash = (Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash
        $actualHash = (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash
        if ($expectedHash -ne $actualHash) {
            throw "APPX asset assets\$name が自前タイルと不一致です（electron-builder のサンプル画像が混入した可能性。windows\resources\appx の配置を確認）"
        }
    }
    Write-Host '  Tile assets verified (custom icons in package)'
}

function Get-SftpgenIdentityVersion {
    param([Parameter(Mandatory = $true)][string]$VersionFile)
    if (-not (Test-Path -LiteralPath $VersionFile)) {
        throw "version.txt not found: $VersionFile"
    }
    $parts = ((Get-Content -LiteralPath $VersionFile -Raw).Trim()).Split('.')
    if ($parts.Length -lt 3) {
        throw "version.txt must be major.minor.patch"
    }
    return "$($parts[0]).$($parts[1]).$($parts[2]).0"
}

function Set-AppxManifestVersion {
    param(
        [string]$ManifestPath,
        [string]$Version
    )
    $text = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    if ($text -notmatch '<Identity[^>]*?\sVersion="([^"]+)"') {
        throw "Identity Version not found in $ManifestPath"
    }
    $current = $Matches[1]
    if ($current -eq $Version) { return }
    $updated = $text -replace '(<Identity[^>]*?\sVersion=")[^"]*(")', "`${1}$Version`${2}"
    [System.IO.File]::WriteAllText($ManifestPath, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Identity Version $current -> $Version"
}

function Set-AppxManifestDependencies {
    param([string]$ManifestPath)
    $text = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $minVersion = '10.0.19041.0'
    $replacement = "<TargetDeviceFamily Name=`"Windows.Desktop`" MinVersion=`"$minVersion`" MaxVersionTested=`"$minVersion`" />"
    if ($text -match '<TargetDeviceFamily[^>]*/>') {
        $updated = $text -replace '<TargetDeviceFamily[^>]*/>', $replacement
    } else {
        throw "TargetDeviceFamily not found in $ManifestPath"
    }
    if ($updated -ne $text) {
        [System.IO.File]::WriteAllText($ManifestPath, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  Dependencies -> $minVersion"
    }
}

function Remove-AppxManifestAllowExternalContent {
    <#
      uap10:AllowExternalContent は「外部ロケーション参照パッケージ（sparse package、
      Add-AppxPackage -ExternalLocation で登録する非 Store 配布向け）」専用。
      Store 提出パッケージに含めると Store 経由のインストールに失敗する
      （認証 10.3.4「App Is Testable — failed to install through the Store」2026-08 実例）。
      POUCHES の Store 提出フローにも含まれていない。混入していたら除去する。
    #>
    param([string]$ManifestPath)
    $text = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    if ($text -notmatch 'uap10:AllowExternalContent') { return }
    $updated = [regex]::Replace($text, '\s*<uap10:AllowExternalContent>[^<]*</uap10:AllowExternalContent>', '')
    [System.IO.File]::WriteAllText($ManifestPath, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Removed uap10:AllowExternalContent (Store install blocker)"
}

function Test-ManifestHasSteFta {
    param([string]$ManifestContent)
    return ($ManifestContent -match 'FileTypeAssociation[^>]*Name="stesite"') -or
        ($ManifestContent -match '<uap:FileType>\.ste</uap:FileType>')
}

function Get-SftpgenPackageDescription {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $pkgPath = Join-Path $ProjectRoot 'package.json'
    if (-not (Test-Path -LiteralPath $pkgPath)) {
        throw "package.json not found: $pkgPath"
    }
    $json = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return [string]$json.description
}

function Set-AppxManifestDescriptions {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if (-not $Description) { return }
    $text = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $escaped = [System.Security.SecurityElement]::Escape($Description)
    $updated = [regex]::Replace($text, '(<Description>)[^<]*(</Description>)', "`${1}$escaped`${2}", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $updated = [regex]::Replace($updated, '(<uap:VisualElements\b[\s\S]*?\bDescription=")[^"]*(")', "`${1}$escaped`${2}", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($updated -ne $text) {
        [System.IO.File]::WriteAllText($ManifestPath, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  Normalized manifest descriptions"
    }
}

function Inject-SteFta {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)

    $content = [System.IO.File]::ReadAllText($ManifestPath)
    if (Test-ManifestHasSteFta -ManifestContent $content) {
        Write-Host "  STE FTA already present"
        return
    }

    $fta = @"
    <uap3:Extension Category="windows.fileTypeAssociation">
      <uap3:FileTypeAssociation Name="stesite">
        <uap:SupportedFileTypes>
          <uap:FileType>.ste</uap:FileType>
        </uap:SupportedFileTypes>
        <uap:DisplayName>Dreamweaver Site Settings</uap:DisplayName>
      </uap3:FileTypeAssociation>
    </uap3:Extension>
"@

    if ($content -match '<Extensions\s*/>') {
        $content = $content -replace '<Extensions\s*/>', ("<Extensions>`r`n" + $fta + "`r`n      </Extensions>")
    } elseif ($content -match '</Extensions>') {
        $content = $content -replace '</Extensions>', ($fta + "`r`n      </Extensions>")
    } elseif ($content -match '</Application>') {
        $content = $content -replace '</Application>', ("    <Extensions>`r`n" + $fta + "`r`n      </Extensions>`r`n    </Application>")
    } else {
        throw "Cannot inject STE FTA in $ManifestPath"
    }

    if ($content -notmatch 'xmlns:uap3=') {
        if ($content -match 'IgnorableNamespaces="([^"]*)"') {
            if ($Matches[1] -notmatch 'uap3') {
                $content = $content -replace 'IgnorableNamespaces="([^"]*)"', 'IgnorableNamespaces="$1 uap3"'
            }
        } elseif ($content -match '<Package\b') {
            $content = $content -replace '(<Package\b[^>]*)(>)', '$1 IgnorableNamespaces="uap3"$2'
        }
        $content = $content -replace '(<Package\b)', '$1 xmlns:uap3="http://schemas.microsoft.com/appx/manifest/uap/windows10/3"'
    }

    [System.IO.File]::WriteAllText($ManifestPath, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Injected .ste FTA"
}
