<#
========================================================================
 Script tu dong cau hinh VPS & Cai dat Sunshine Game Stream
 - Doi mat khau Windows (Mac dinh hoac tu nhap)
 - Tat Firewall de mo port Sunshine
 - Tai va cai dat Sunshine moi nhat tu GitHub
 - Mo giao dien Web UI (localhost:47990) tren trinh duyet
 - Hien thi thong tin IPv4 va tai khoan ket noi
========================================================================
#>

# 1. Kiem tra va yeu cau quyen Administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Dang yeu cau quyen Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   BAT DAU CAU HINH VPS & CAI DAT SUNSHINE STREAMING      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 2. Thiet lap mat khau may (User Windows)
$currentUser =$env:USERNAME
Write-Host "[1/5] THIET LAP MAT KHAU CHO USER: $currentUser" -ForegroundColor Green
Write-Host "  [1] Dung mat khau mac dinh: @Noobdz123."
Write-Host "  [2] Tu nhap mat khau moi theo y ban"
$choice = Read-Host "-> Chon (Nhan Enter de chon mac dinh [1])"

$finalPassword = ""

if ($choice -eq "2") {
    $match =$false
    while (-not $match) {$p1 = Read-Host "-> Nhap mat khau moi" -AsSecureString
        $p2 = Read-Host "-> Xac nhan lai mat khau moi" -AsSecureString
        
        $p1_plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
        $p2_plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
        
        if ($p1_plain -eq $p2_plain -and$p1_plain.Length -gt 0) {
            $finalPassword =$p1_plain
            $match =$true
        } else {
            Write-Host "[-] Mat khau khong khop hoac de trong! Vui long nhap lai." -ForegroundColor Red
        }
    }
} else {
    $finalPassword = "@Noobdz123."
}

# Doi mat khau tai khoan
try {
    net user "$currentUser" "$finalPassword" | Out-Null
    Write-Host "[+] Da doi mat khau cho user '$currentUser' thanh cong!" -ForegroundColor Green
} catch {
    Write-Host "[-] Khong the doi mat khau qua net user: $_" -ForegroundColor Red
}

Write-Host ""

# 3. Tat Windows Firewall de mo port Sunshine
Write-Host "[2/5] TAT TUONG LUA (WINDOWS FIREWALL)..." -ForegroundColor Green
try {
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
    Write-Host "[+] Da tat toan bo Windows Firewall (Domain, Public, Private)." -ForegroundColor Green
} catch {
    Write-Host "[-] Loi khi tat Firewall: $_" -ForegroundColor Red
}

Write-Host ""

# 4. Tai va cai dat Sunshine moi nhat tu GitHub
Write-Host "[3/5] TAI VA CAI DAT SUNSHINE..." -ForegroundColor Green
$installerPath = "$env:TEMP\sunshine-installer.exe"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    Write-Host "-> Dang kiem tra phien ban moi nhat tu GitHub LizardByte/Sunshine..." -ForegroundColor Gray
    
    $apiUrl = "https://api.github.com/repos/LizardByte/Sunshine/releases/latest"
    $releaseInfo = Invoke-RestMethod -Uri$apiUrl -Headers @{"User-Agent"="PowerShell"}
    
    $asset =$releaseInfo.assets | Where-Object { $_.name -like "*sunshine-windows-installer.exe" -or $_.name -like "sunshine-windows-*.exe" } | Select-Object -First 1
    
    if ($asset) {
        $downloadUrl =$asset.browser_download_url
        Write-Host "-> Dang tai: $($asset.name)..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $downloadUrl -OutFile$installerPath
        
        Write-Host "-> Dang tien hanh cai dat ngam (Silent Install)..." -ForegroundColor Gray
        Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
        Write-Host "[+] Da cai dat Sunshine thanh cong!" -ForegroundColor Green
    } else {
        throw "Khong tim thay file exe bo cai trong release moi nhat."
    }
} catch {
    Write-Host "[-] Khong tai duoc tu GitHub release ($($_)). Chuyen sang cai qua winget..." -ForegroundColor Yellow
    winget install LizardByte.Sunshine --silent --accept-package-agreements --accept-source-agreements
}

Write-Host ""

# 5. Khoi chay Sunshine Service & Mo Web UI
Write-Host "[4/5] KHOI CHAY SUNSHINE & MO TRINH DUYET..." -ForegroundColor Green
$sunshineExe = "C:\Program Files\Sunshine\sunshine.exe"
if (Test-Path $sunshineExe) {
    Start-Process -FilePath $sunshineExe -WindowStyle Hidden
}

Start-Sleep -Seconds 3

# Mo link quan ly Sunshine tren trinh duyet mac dinh
$webUiUrl = "https://localhost:47990"
Write-Host "-> Dang mo Web UI tai: $webUiUrl" -ForegroundColor Gray
Start-Process $webUiUrl

Write-Host ""

# 6. Lay dia chi IPv4 Public cua may
Write-Host "[5/5] LAY THONG TIN DIA CHI IPV4 CUA VPS..." -ForegroundColor Green
$publicIp = "Khong xac dinh"
try {
    $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 6).Trim()
} catch {
    try {
        $publicIp = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 6).Trim()
    } catch {
        $publicIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Where-Object { $_.IPAddress -notlike "169.*" -and $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress
    }
}

# Tom tat thong tin cho nguoi dung
Clear-Host
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "             CAI DAT HOAN TAT THANH CONG!                 " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "THONG TIN KET NOI VPS:" -ForegroundColor Yellow
Write-Host "  - IPv4 Public cua VPS   : $publicIp" -ForegroundColor Cyan
Write-Host "
