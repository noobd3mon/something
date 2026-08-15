<#
.SYNOPSIS
    Automated Sunshine & VPS Setup Script for Windows
.DESCRIPTION
    1. Sets Windows User Password (Default: @Noobdz123 or Custom with confirmation).
    2. Completely disables Windows Firewall for remote streaming.
    3. Downloads and installs Sunshine silently.
    4. Fetches Public IPv4 address.
    5. Opens Sunshine Web UI in the default browser.
.NOTES
    Run as Administrator.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         AUTO SETUP SUNSHINE & VPS CONFIGURATION          " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------
# 1. THIET LAP MAT KHAU WINDOWS
# ---------------------------------------------------------
$currentUser = [System.Environment]::UserName
Write-Host "[+] Nguoi dung hien tai tren VPS: $currentUser" -ForegroundColor Green

$defaultPass = "@Noobdz123"
Write-Host "Lua chon dat mat khau cho Windows:" -ForegroundColor Cyan
Write-Host "  [1] Dung mat khau mac dinh: $defaultPass (Nhan Enter hoac chon 1)" -ForegroundColor Gray
Write-Host "  [2] Tu nhap mat khau moi" -ForegroundColor Gray
$choice = Read-Host "Nhap lua chon [1/2] (Mac dinh 1)"

$finalPass = $defaultPass

if ($choice -eq "2") {
    while ($true) {
        $p1 = Read-Host "Nhap mat khau moi" -AsSecureString
        $p2 = Read-Host "Xac nhan lai mat khau" -AsSecureString
        
        $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1)
        $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2)
        $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)
        
        if ($plain1 -eq $plain2 -and -not [string]::IsNullOrWhiteSpace($plain1)) {
            $finalPass = $plain1
            Write-Host "[OK] Mat khau xac nhan hop le!" -ForegroundColor Green
            break
        } else {
            Write-Host "[!] Mat khau khong khop hoac de trong, vui long thu lai.`n" -ForegroundColor Red
        }
    }
}

try {
    net user "$currentUser" "$finalPass" | Out-Null
    Write-Host "[+] Da set mat khau Windows thanh cong!" -ForegroundColor Green
} catch {
    Write-Warning "Khong the set mat khau qua net user: $_"
}

# ---------------------------------------------------------
# 2. TAT TUONG LUA (WINDOWS FIREWALL)
# ---------------------------------------------------------
Write-Host "`n[+] Dang tat Windows Firewall de mo toan bo port VPS..." -ForegroundColor Cyan
try {
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
    Write-Host "[+] Da tat hoan toan Windows Firewall (Domain, Public, Private)!" -ForegroundColor Green
} catch {
    Write-Warning "Khong the tat Firewall: $_"
}

# ---------------------------------------------------------
# 3. TAI VA CAI DAT SUNSHINE
# ---------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$TempDir = [System.IO.Path]::GetTempPath()
$InstallerPath = Join-Path -Path $TempDir -ChildPath "sunshine-installer.exe"
$DownloadUrl = "https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-windows-installer.exe"

Write-Host "`n[+] Dang tai Sunshine Installer ban moi nhat..." -ForegroundColor Cyan
try {
    $OriginalProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    $ProgressPreference = $OriginalProgressPreference
    Write-Host "[+] Tai thanh cong: $InstallerPath" -ForegroundColor Green
} catch {
    Write-Error "Loi tai Sunshine: $_"
    Exit
}

Write-Host "[+] Dang cai dat Sunshine (Silent)..." -ForegroundColor Cyan
try {
    $process = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -PassThru -Wait
    Write-Host "[+] Cai dat Sunshine hoan tat!" -ForegroundColor Green
} catch {
    Write-Error "Loi cai dat Sunshine: $_"
    Exit
}

# Setup thong tin tai khoan dang nhap Sunshine mac dinh (sunshine / @Noobdz123)
$sunshineExe = "C:\Program Files\Sunshine\sunshine.exe"
if (Test-Path $sunshineExe) {
    try {
        & "$sunshineExe" --creds admin "$finalPass" | Out-Null
        Write-Host "[+] Da set tai khoan Sunshine: admin / $finalPass" -ForegroundColor Green
    } catch {}
}

# Xoa file cai dat
if (Test-Path $InstallerPath) {
    Remove-Item -Path $InstallerPath -Force
}

# ---------------------------------------------------------
# 4. LAY IPV4 VA THONG TIN KET NOI
# ---------------------------------------------------------
Write-Host "`n[+] Dang lay dia chi IPv4 cua VPS..." -ForegroundColor Cyan
$publicIp = "Khong lay duoc IP"
try {
    $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5).Trim()
} catch {
    try {
        $publicIp = (Invoke-RestMethod -Uri "https://icanhazip.com" -TimeoutSec 5).Trim()
    } catch {}
}

# ---------------------------------------------------------
# 5. MO TRINH DUYET VA HIEN THI THONG TIN
# ---------------------------------------------------------
Write-Host "[+] Dang mo Sunshine Web UI tren trinh duyet mac dinh..." -ForegroundColor Cyan
Start-Process "https://localhost:47990"

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "                 CAI DAT HOAN TAT THIET LAP!              " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " 1. IP Public VPS (Moonlight IP) : $publicIp" -ForegroundColor Cyan
Write-Host " 2. Mat khau Windows VPS         : $finalPass" -ForegroundColor Cyan
Write-Host " 3. Web UI Sunshine (Local)      : https://localhost:47990" -ForegroundColor Cyan
Write-Host " 4. Web UI Sunshine (Tu xa)      : https://${publicIp}:47990" -ForegroundColor Cyan
Write-Host " 5. Dang nhap Sunshine Web UI    : admin / $finalPass" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Luu y: Tren trinh duyet, hay chon 'Advanced' -> 'Proceed to localhost' vi chung chi SSL tu sinh." -ForegroundColor Gray
