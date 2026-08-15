<#
.SYNOPSIS
    Automated Sunshine & VPS Setup Script
.DESCRIPTION
    - Set Windows password (@Noobdz123 default or custom input with confirmation)
    - Disable Windows Firewall completely
    - Auto-fetch latest Sunshine release using curl.exe
    - Configure Sunshine Web UI admin credentials
    - Fetch Public IPv4 and open Sunshine Web UI in browser
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
Write-Host "`n[+] Dang tat Windows Firewall de mo toan bo port..." -ForegroundColor Cyan
try {
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
    netsh advfirewall set allprofiles state off | Out-Null
    Write-Host "[+] Da tat hoan toan Windows Firewall!" -ForegroundColor Green
} catch {
    Write-Warning "Khong the tat Firewall: $_"
}

# ---------------------------------------------------------
# 3. TAI VA CAI DAT SUNSHINE (DUNG CURL.EXE)
# ---------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$TempDir = [System.IO.Path]::GetTempPath()
$InstallerPath = Join-Path -Path $TempDir -ChildPath "sunshine-installer.exe"
if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force }

Write-Host "`n[+] Dang tim link tai Sunshine Release moi nhat..." -ForegroundColor Cyan

$DownloadUrls = @()
try {
    $api = Invoke-RestMethod -Uri "https://api.github.com/repos/LizardByte/Sunshine/releases/latest" -Headers @{"User-Agent"="Mozilla/5.0"} -TimeoutSec 10
    $assets = $api.assets | Where-Object { $_.name -like "*installer.exe" -or ($_.name -like "*.exe" -and $_.name -notlike "*portable*") }
    foreach ($a in $assets) {
        $DownloadUrls += $a.browser_download_url
    }
} catch {}

# URL fallback neu API bi gioi han
$DownloadUrls += "https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-windows-amd64-installer.exe"
$DownloadUrls += "https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-windows-installer.exe"

$downloadSuccess = $false
$curlExe = "$env:SystemRoot\System32\curl.exe"

foreach ($url in $DownloadUrls) {
    Write-Host "[+] Dang thu tai tu: $url" -ForegroundColor Cyan
    
    if (Test-Path $curlExe) {
        # Dung curl.exe goc cua Windows: -L (follow redirect), -f (fail neu 404), -k (insecure ssl fallback), -s (silent)
        & $curlExe -f -L --retry 3 --retry-delay 2 -k -o "$InstallerPath" "$url"
    } else {
        # Fallback neu VPS khong co curl.exe
        try {
            $OriginalProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $InstallerPath -UseBasicParsing -UserAgent "Mozilla/5.0"
            $ProgressPreference = $OriginalProgressPreference
        } catch {}
    }

    # Kiem tra file phai ton tai va dung luong > 10MB (tranh file HTML loi)
    if ((Test-Path $InstallerPath) -and ((Get-Item $InstallerPath).Length -gt 10485760)) {
        $fileSizeMB = [math]::Round(((Get-Item $InstallerPath).Length / 1MB), 2)
        Write-Host "[+] Tai thanh cong! Dung luong: $fileSizeMB MB" -ForegroundColor Green
        $downloadSuccess = $true
        break
    } else {
        if (Test-Path $InstallerPath) { Remove-Item -Path $InstallerPath -Force }
    }
}

if (-not $downloadSuccess) {
    Write-Error "Khong the tai bo cai Sunshine. Vui long kiem tra lai ket noi mang."
    Exit
}

Write-Host "`n[+] Dang cai dat Sunshine (Silent)..." -ForegroundColor Cyan
try {
    $process = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -PassThru -Wait
    Write-Host "[+] Cai dat Sunshine hoan tat!" -ForegroundColor Green
} catch {
    Write-Error "Loi khi chay trinh cai dat: $_"
    Exit
}

# Khoi tao tai khoan Sunshine Web UI
$sunshineExe = "C:\Program Files\Sunshine\sunshine.exe"
if (Test-Path $sunshineExe) {
    try {
        & "$sunshineExe" --creds admin "$finalPass" | Out-Null
        Write-Host "[+] Da set tai khoan Web UI Sunshine: admin / $finalPass" -ForegroundColor Green
    } catch {}
}

# Don dep installer
if (Test-Path $InstallerPath) {
    Remove-Item -Path $InstallerPath -Force
}

# ---------------------------------------------------------
# 4. LAY IPV4 VA THONG TIN KET NOI
# ---------------------------------------------------------
Write-Host "`n[+] Dang lay dia chi IPv4 Public cua VPS..." -ForegroundColor Cyan
$publicIp = "Khong xac dinh"
$ipServices = @(
    "https://api.ipify.org",
    "https://icanhazip.com",
    "https://ifconfig.me/ip",
    "https://checkip.amazonaws.com"
)

foreach ($srv in $ipServices) {
    try {
        if (Test-Path $curlExe) {
            $res = (& $curlExe -s -m 3 $srv).Trim()
        } else {
            $res = (Invoke-RestMethod -Uri $srv -TimeoutSec 3).Trim()
        }
        if ($res -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$") {
            $publicIp = $res
            break
        }
    } catch {}
}

# ---------------------------------------------------------
# 5. MO TRINH DUYET VA HIEN THI THONG TIN
# ---------------------------------------------------------
Write-Host "[+] Dang mo Sunshine Web UI tren trinh duyet..." -ForegroundColor Cyan
Start-Process "https://localhost:47990"

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "                 CAI DAT HOAN TAT THIET LAP!              " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " 1. IP Public VPS (Moonlight IP) : $publicIp" -ForegroundColor Cyan
Write-Host " 2. Mat khau Windows VPS         : $finalPass" -ForegroundColor Cyan
Write-Host " 3. Web UI Sunshine (Local)      : https://localhost:47990" -ForegroundColor Cyan
Write-Host " 4. Web UI Sunshine (Tu xa)      : https://${publicIp}:47990" -ForegroundColor Cyan
Write-Host " 5. Tai khoan Sunshine Web UI    : admin / $finalPass" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Luu y: Trinh duyet bao SSL Warning -> bam 'Advanced' -> 'Proceed to localhost'." -ForegroundColor Gray
