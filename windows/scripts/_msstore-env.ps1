#Requires -Version 5.1
# Studio Tomippe 共通 — ~/.msstore-env + プロジェクト .env

function Import-MsStoreEnvFile {
    param([string]$File)

    if (-not (Test-Path -LiteralPath $File)) { return }

    [System.IO.File]::ReadAllLines($File) | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { return }
        if ($line -match '^\s*export\s+(.+)$') { $line = $Matches[1].Trim() }
        if ($line -notmatch '=') { return }

        $name, $value = $line -split '=', 2
        $name = $name.Trim()
        $value = $value.Trim().Trim('"').Trim("'")

        if ($name -and $value) {
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

function Load-MsStoreEnv {
    param([string]$ProjectRoot = "")

    Import-MsStoreEnvFile 'Y:\.msstore-env'
    Import-MsStoreEnvFile (Join-Path $env:USERPROFILE '.msstore-env')
    if ($ProjectRoot) {
        Import-MsStoreEnvFile (Join-Path $ProjectRoot '.env')
    }
}

function Resolve-MsStoreSigningPfx {
    param([string]$ProjectRoot = "")

    $candidates = @()
    if ($env:MS_STORE_SIGNING_PFX) { $candidates += $env:MS_STORE_SIGNING_PFX }
    if ($ProjectRoot) {
        $candidates += (Join-Path $ProjectRoot '..\pouches\native\windows\signing\StudioTomippe-MSIX.pfx')
    }

    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }
    return $null
}

function Find-SdkSignTool {
    $candidates = @()
    foreach ($root in @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "${env:ProgramFiles}\Windows Kits\10\bin")) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $candidates += Get-ChildItem -LiteralPath $root -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -like '*\x64*' }
    }
    if ($candidates.Count -eq 0) {
        throw 'signtool.exe not found. Install Windows 10/11 SDK.'
    }
    return ($candidates | Sort-Object {
            $ver = $null
            [void][version]::TryParse($_.Directory.Parent.Name, [ref]$ver)
            if ($ver) { $ver } else { [version]'0.0.0.0' }
        } -Descending | Select-Object -First 1).FullName
}

function Sign-StorePackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [string]$PfxPath = "",
        [string]$PfxPassword = ""
    )

    if (-not $PfxPath) { $PfxPath = $env:MS_STORE_SIGNING_PFX }
    if (-not $PfxPassword) { $PfxPassword = $env:MS_STORE_SIGNING_PFX_PASSWORD }

    if (-not $PfxPath -or -not (Test-Path -LiteralPath $PfxPath)) {
        throw "PFX not found. Set MS_STORE_SIGNING_PFX in %USERPROFILE%\.msstore-env"
    }
    if (-not $PfxPassword) {
        throw 'PFX password required. Set MS_STORE_SIGNING_PFX_PASSWORD in %USERPROFILE%\.msstore-env'
    }

    $signTool = Find-SdkSignTool
    Write-Host "  Signing: $PackagePath" -ForegroundColor Gray
    & $signTool sign /fd SHA256 /f $PfxPath /p $PfxPassword /a $PackagePath
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed for $PackagePath (exit $LASTEXITCODE)"
    }
}
