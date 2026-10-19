#Requires -RunAsAdministrator
<#
    .SYNOPSIS
        Optimized Windows 11 Pro Cleanup & Optimization Script (Offline Mode)
#>

$ErrorActionPreference = "SilentlyContinue"

function Write-Step($Text) {
    Write-Host "`n== $Text ==" -ForegroundColor Cyan
}

# --- Admin check ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Error: Please run PowerShell as Administrator!" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit
}

# --- 1. Temp files and cache cleanup ---
Write-Step "Cleaning temporary folders and cache"

$foldersToClean = @(
    "$env:TEMP",
    "$env:SystemRoot\Temp",
    "$env:SystemRoot\Prefetch",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
)

foreach ($folder in $foldersToClean) {
    if (Test-Path $folder) {
        Get-ChildItem -Path "$folder\*" -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
            } catch {}
        }
        Write-Host "Cleaned: $folder" -ForegroundColor Green
    }
}

# --- 2. Windows Update cache cleanup ---
Write-Step "Cleaning Windows Update cache"
try {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    $sd = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path $sd) {
        Get-ChildItem -Path "$sd\*" -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop } catch {}
        }
        Write-Host "Windows Update download cache removed." -ForegroundColor Green
    }
}
catch {
    Write-Warning "Could not clean update cache (service might be busy)."
}
finally {
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
}

# --- 3. Component Store (WinSxS) optimization ---
Write-Step "Optimizing Component Store (WinSxS)"
Write-Host "Compressing system component store (this may take a couple of minutes)..." -ForegroundColor Yellow
try {
    DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
    Write-Host "Component store successfully optimized." -ForegroundColor Green
}
catch {
    Write-Warning "DISM completed with a warning or error."
}

# --- 4. Disable background services (offline profile) ---
Write-Step "Disabling background services (telemetry & updates)"
$servicesToDisable = @("DiagTrack", "lfsvc", "TrkWks", "PhoneSvc", "wuauserv")

foreach ($name in $servicesToDisable) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        try {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            Write-Host "Service $name -> Disabled" -ForegroundColor Green
        }
        catch {
            Write-Warning "Could not modify service $name"
        }
    }
}

# --- 5. Cleanmgr disk cleanup ---
Write-Step "Running Disk Cleanup (Cleanmgr)"
try {
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Value 2 -ErrorAction SilentlyContinue
    }
    Start-Process cleanmgr.exe -ArgumentList "/sagerun:1" -NoNewWindow -Wait
    Write-Host "Disk cleanup completed." -ForegroundColor Green
}
catch {
    Write-Warning "Cleanmgr skipped."
}

# --- Completion ---
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Done! The system is fully cleaned." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Read-Host "Press Enter to exit..."