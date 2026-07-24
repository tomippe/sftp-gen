#Requires -Version 5.1

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

function Set-AppxManifestAllowExternalContent {
    param([string]$ManifestPath)
    $text = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    if ($text -match 'uap10:AllowExternalContent\s*>\s*true') { return }
    if ($text -notmatch 'xmlns:uap10=') {
        $text = $text -replace '(<Package\b[^>]*)(>)', '$1 xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"$2'
    }
    if ($text -match 'IgnorableNamespaces="([^"]*)"') {
        if ($Matches[1] -notmatch 'uap10') {
            $text = $text -replace 'IgnorableNamespaces="([^"]*)"', 'IgnorableNamespaces="$1 uap10"'
        }
    } elseif ($text -match '<Package\b') {
        $text = $text -replace '(<Package\b[^>]*)(>)', '$1 IgnorableNamespaces="uap10"$2'
    }
    if ($text -match '<Properties>') {
        $text = $text -replace '<Properties>', "<Properties>`r`n    <uap10:AllowExternalContent>true</uap10:AllowExternalContent>"
    } else {
        throw "Properties element not found in $ManifestPath"
    }
    [System.IO.File]::WriteAllText($ManifestPath, $text, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  AllowExternalContent=true (Electron unpack)"
}

function Test-ManifestHasSteFta {
    param([string]$ManifestContent)
    return ($ManifestContent -match 'FileTypeAssociation[^>]*Name="stesite"') -or
        ($ManifestContent -match '<uap:FileType>\.ste</uap:FileType>')
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
