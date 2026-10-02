param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-Stage06HostProfile {
    $os = Get-CimInstance Win32_OperatingSystem
    $caption = [string]$os.Caption
    $version = [string]$os.Version
    $architecture = [string]$os.OSArchitecture

    $is64 = [Environment]::Is64BitOperatingSystem
    $normalized = "UNKNOWN"
    $class = "UNSUPPORTED"

    if (-not $is64) {
        $normalized = "WINDOWS_X86_32_BIT"
        $class = "UNSUPPORTED"
    }
    elseif ($caption -match "Windows Server 2012 R2") {
        $normalized = "WINDOWS_SERVER_2012_R2_X64"
        $class = "DEFERRED"
    }
    elseif ($caption -match "Windows Server 2016") {
        $normalized = "WINDOWS_SERVER_2016_X64"
        $class = "COMPATIBILITY"
    }
    elseif ($caption -match "Windows Server 2019") {
        $normalized = "WINDOWS_SERVER_2019_X64"
        $class = "COMPATIBILITY"
    }
    elseif ($caption -match "Windows Server 2022") {
        $normalized = "WINDOWS_SERVER_2022_X64"
        $class = "PREFERRED"
    }
    elseif ($caption -match "Windows 11") {
        $normalized = "WINDOWS_11_X64"
        $class = "PREFERRED"
    }
    elseif ($caption -match "Windows 10") {
        $normalized = "WINDOWS_10_X64"
        $class = "COMPATIBILITY"
    }

    [pscustomobject]@{
        caption = $caption
        version = $version
        architecture = $architecture
        normalized = $normalized
        validation_class = $class
        powershell_version = $PSVersionTable.PSVersion.ToString()
        is_64_bit = $is64
    }
}

$profile = Get-Stage06HostProfile

if ($Json) {
    $profile | ConvertTo-Json -Depth 4
}
else {
    Write-Host "Katarina Stage 06 host check"
    Write-Host "OS:            $($profile.caption)"
    Write-Host "Version:       $($profile.version)"
    Write-Host "Architecture:  $($profile.architecture)"
    Write-Host "Normalized:    $($profile.normalized)"
    Write-Host "Class:         $($profile.validation_class)"
    Write-Host "PowerShell:    $($profile.powershell_version)"
}

switch ($profile.validation_class) {
    "PREFERRED" {
        Write-Host "PASS: preferred Stage 06 validation host."
    }
    "COMPATIBILITY" {
        Write-Host "PASS: Stage 06 compatibility-validation host."
    }
    "DEFERRED" {
        throw "DEFERRED: Windows Server 2012 R2 is intentionally outside the current Stage 06 validation baseline."
    }
    default {
        throw "UNSUPPORTED: this Windows host is outside the current Stage 06 validation baseline."
    }
}
