<#
========================================================================
 Script tự động cấu hình VPS & Cài đặt Sunshine Game Stream
 - Đổi mật khẩu Windows (Mặc định hoặc tự nhập)
 - Tắt Firewall để mở toàn bộ port kết nối ngoài
 - Tải và cài đặt Sunshine phiên bản mới nhất từ GitHub
 - Mở giao diện Web UI (localhost:47990) trên trình duyệt
 - Hiển thị thông tin IPv4 và tài khoản kết nối
========================================================================
#>

# 1. Kiểm tra và yêu cầu quyền Administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Đang yêu cầu quyền Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   BẮT ĐẦU CẤU HÌNH VPS & CÀI ĐẶT SUNSHINE STREAMING      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 2. Thiết lập mật khẩu máy (User Windows)
$currentUser = $env:USERNAME
Write-Host "[1/5] THIẾT LẬP MẬT KHẨU CHO USER: $currentUser" -ForegroundColor Green
Write-Host "  [1] Dùng mật khẩu mặc định: @Noobdz123."
Write-Host "  [2] Tự nhập mật khẩu mới theo ý bạn"
$choice = Read-Host "-> Chọn (Nhấn Enter để chọn mặc định [1])"

$finalPassword = ""

if ($choice -eq "2") {
    $match = $false
    while (-not $match) {
        $p1 = Read-Host "-> Nhập mật khẩu mới" -AsSecureString
        $p2 = Read-Host "-> Xác nhận lại mật khẩu mới" -AsSecureString
        
        $p1_plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
        $p2_plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
        
        if ($p1_plain -eq $p2_plain -and $p1_plain.Length -gt 0) {
            $finalPassword = $p1_plain
            $match = $true
        } else {
            Write-Host "[-] Mật khẩu không khớp hoặc để trống! Vui lòng nhập lại." -ForegroundColor Red
        }
    }
} else {
    $finalPassword = "@Noobdz123."
}

# Đổi mật khẩu tài khoản
try {
    net user "$currentUser" "$finalPassword" | Out-Null
    Write-Host "[+] Đã đổi mật khẩu cho user '$currentUser' thành công!" -ForegroundColor Green
} catch {
    Write-Host "[-] Không thể đổi mật khẩu qua net user: $_" -ForegroundColor Red
}

Write-Host ""

# 3. Tắt Windows Firewall để mở port Sunshine
Write-Host "[2/5] TẮT TƯỜNG LỬA (WINDOWS FIREWALL)..." -ForegroundColor Green
try {
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
    Write-Host "[+] Đã tắt toàn bộ Windows Firewall (Domain, Public, Private)." -ForegroundColor Green
} catch {
    Write-Host "[-] Lỗi khi tắt Firewall: $_" -ForegroundColor Red
}

Write-Host ""

# 4. Tải và cài đặt Sunshine mới nhất từ GitHub
Write-Host "[3/5] TẢI VÀ CÀI ĐẶT SUNSHINE..." -ForegroundColor Green
$installerPath = "$env:TEMP\sunshine-installer.exe"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    Write-Host "-> Đang kiểm tra phiên bản mới nhất từ GitHub LizardByte/Sunshine..." -ForegroundColor Gray
    
    $apiUrl = "https://api.github.com/repos/LizardByte/Sunshine/releases/latest"
    $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers @{"User-Agent"="PowerShell"}
    
    $asset = $releaseInfo.assets | Where-Object { $_.name -like "*sunshine-windows-installer.exe" -or $_.name -like "sunshine-windows-*.exe" } | Select-Object -First 1
    
    if ($asset) {
        $downloadUrl = $asset.browser_download_url
        Write-Host "-> Đang tải: $($asset.name)..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        
        Write-Host "-> Đang tiến hành cài đặt ngầm (Silent Install)..." -ForegroundColor Gray
        Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
        Write-Host "[+] Đã cài đặt Sunshine thành công!" -ForegroundColor Green
    } else {
        throw "Không tìm thấy file exe bộ cài trong release mới nhất."
    }
} catch {
    Write-Host "[-] Không tải được từ GitHub release ($($_)). Chuyển sang cài qua winget..." -ForegroundColor Yellow
    winget install LizardByte.Sunshine --silent --accept-package-agreements --accept-source-agreements
}

Write-Host ""

# 5. Khởi chạy Sunshine Service & Mở Web UI
Write-Host "[4/5] KHỞI CHẠY SUNSHINE & MỞ TRÌNH DUYỆT..." -ForegroundColor Green
$sunshineExe = "C:\Program Files\Sunshine\sunshine.exe"
if (Test-Path $sunshineExe) {
    Start-Process -FilePath $sunshineExe -WindowStyle Hidden
}

Start-Sleep -Seconds 3

# Mở link quản lý Sunshine trên trình duyệt mặc định
$webUiUrl = "https://localhost:47990"
Write-Host "-> Đang mở Web UI tại: $webUiUrl" -ForegroundColor Gray
Start-Process $webUiUrl

Write-Host ""

# 6. Lấy địa chỉ IPv4 Public của máy
Write-Host "[5/5] LẤY THÔNG TIN ĐỊA CHỈ IPV4 CỦA VPS..." -ForegroundColor Green
$publicIp = "Không xác định"
try {
    $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 6).Trim()
} catch {
    try {
        $publicIp = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 6).Trim()
    } catch {
        $publicIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Where-Object { $_.IPAddress -notlike "169.*" -and $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress
    }
}

# Tóm tắt thông tin cho người dùng
Clear-Host
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "             CÀI ĐẶT HOÀN TẤT THÀNH CÔNG!                 " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "THÔNG TIN KẾT NỐI VPS:" -ForegroundColor Yellow
Write-Host "  - IPv4 Public của VPS   : $publicIp" -ForegroundColor Cyan
Write-Host "  - Tên User Windows      : $currentUser" -ForegroundColor Cyan
Write-Host "  - Mật khẩu User Windows : $finalPassword" -ForegroundColor Cyan
Write-Host ""
Write-Host "CÁC BƯỚC TIẾP THEO:" -ForegroundColor Yellow
Write-Host "  1. Trình duyệt đã mở trang https://localhost:47990 (Bỏ qua cảnh báo SSL/HTTPS nếu có)."
Write-Host "  2. Đặt Username và Password quản trị cho Web UI Sunshine lần đầu tiên đăng nhập."
Write-Host "  3. Mở Moonlight trên máy khách (Client) -> Nhập IP: $publicIp để ghép nối mã PIN."
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Read-Host "Nhấn Enter để kết thúc script..."
