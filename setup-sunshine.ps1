<#
================================================================================
 setup-sunshine.ps1  --  Tu dong cai dat + cau hinh Sunshine tren VPS Windows
--------------------------------------------------------------------------------
 Cac buoc script tu lam:
   1. Kiem tra quyen Administrator
   2. Tai + cai dat Sunshine im lang (uu tien MSI, fallback EXE)
   3. Bat dich vu am thanh Windows (Audiosrv + AudioEndpointBuilder, startup = auto)
      va tu cai virtual audio driver VB-CABLE khi may khong co card am thanh
   4. Bat service SunshineService va cho tu dong chay cung Windows
   5. Mo firewall cho cac port cua Sunshine, roi TAT Windows Firewall (yeu cau VPS)
   6. Dat mat khau tai khoan Windows (mac dinh @Noobdz123 hoac tu nhap + confirm)
   7. Dat luon user/pass dang nhap Web UI cua Sunshine
   8. Mo https://localhost:47990 bang trinh duyet mac dinh
   9. In ra IPv4 noi bo + IPv4 public de ket noi tu ben ngoai
--------------------------------------------------------------------------------
 CACH DUNG (PowerShell -> Run as Administrator):

   # 1 lenh, dung mat khau mac dinh / nhap mat khau khi duoc hoi
   irm https://raw.githubusercontent.com/USER/REPO/main/setup-sunshine.ps1 | iex

   # Khong hoi gi ca, ep dung mat khau mac dinh @Noobdz123
   $env:SUNSHINE_USE_DEFAULT_PASSWORD='1'; irm https://raw.githubusercontent.com/USER/REPO/main/setup-sunshine.ps1 | iex

   # Truyen mat khau rieng qua tham so
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/USER/REPO/main/setup-sunshine.ps1))) -Password 'MatKhauCuaBan'
--------------------------------------------------------------------------------
 Luu y: file khong dung ky tu co dau de tranh loi encoding tren PowerShell 5.1.
================================================================================
#>

[CmdletBinding()]
param(
    # Mat khau Windows muon dat. De trong = hoi truc tiep / dung mac dinh.
    [string]$Password,

    # Tai khoan Windows can doi mat khau (mac dinh: user dang dang nhap).
    [string]$User,

    # Ep dung mat khau mac dinh @Noobdz123, khong hoi gi.
    [switch]$UseDefaultPassword,

    # Bo qua buoc doi mat khau Windows.
    [switch]$SkipPassword,

    # Giu nguyen Windows Firewall (chi them rule, khong tat firewall).
    [switch]$KeepFirewall,

    # Khong tu mo trinh duyet.
    [switch]$NoBrowser,

    # Khong dat user/pass cho Web UI Sunshine.
    [switch]$SkipWebUiCreds,

    # Ten dang nhap Web UI Sunshine.
    [string]$WebUiUser = 'admin',

    # Bo qua viec cai virtual audio driver (VB-CABLE).
    [switch]$SkipVirtualAudio,

    # Cai VB-CABLE du may da co thiet bi phat am thanh.
    [switch]$ForceVirtualAudio,

    # Link .zip driver pack VB-CABLE khac (neu muon tu chon phien ban).
    [string]$VirtualAudioUrl,

    # Cai lai Sunshine du da co san.
    [switch]$Force
)

# ------------------------------------------------------------------ Cau hinh --
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$script:DefaultPassword = '@Noobdz123'
$script:WebUiPort       = 47990
$script:ServiceName     = 'SunshineService'
$script:LogFile         = Join-Path $env:ProgramData 'sunshine-setup.log'
$script:TcpPorts        = @('47984-47990', '48010')
$script:UdpPorts        = @('5353', '47998-48010', '48100-48110')
$script:VbCableUrl      = 'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack43.zip'
$script:VirtualAudioRe  = 'VB-Audio|VB-CABLE|CABLE Input|Virtual Cable|Virtual Audio'

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# Cho phep cau hinh qua bien moi truong (huu ich khi chay kieu "irm ... | iex")
if (-not $Password -and $env:SUNSHINE_PASSWORD)                     { $Password = $env:SUNSHINE_PASSWORD }
if (-not $User -and $env:SUNSHINE_USER)                             { $User = $env:SUNSHINE_USER }
if ($env:SUNSHINE_USE_DEFAULT_PASSWORD -eq '1')                     { $UseDefaultPassword = $true }
if ($env:SUNSHINE_SKIP_PASSWORD -eq '1')                            { $SkipPassword = $true }
if ($env:SUNSHINE_KEEP_FIREWALL -eq '1')                            { $KeepFirewall = $true }
if ($env:SUNSHINE_NO_BROWSER -eq '1')                               { $NoBrowser = $true }
if ($env:SUNSHINE_SKIP_WEBUI_CREDS -eq '1')                         { $SkipWebUiCreds = $true }
if ($env:SUNSHINE_FORCE -eq '1')                                    { $Force = $true }
if ($env:SUNSHINE_SKIP_VIRTUAL_AUDIO -eq '1')                       { $SkipVirtualAudio = $true }
if ($env:SUNSHINE_FORCE_VIRTUAL_AUDIO -eq '1')                      { $ForceVirtualAudio = $true }
if (-not $VirtualAudioUrl -and $env:SUNSHINE_VIRTUAL_AUDIO_URL)     { $VirtualAudioUrl = $env:SUNSHINE_VIRTUAL_AUDIO_URL }
if ($VirtualAudioUrl)                                               { $script:VbCableUrl = $VirtualAudioUrl }

# ------------------------------------------------------------------- Helpers --
function Write-Line {
    param([string]$Text = '', [string]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
    try { Add-Content -Path $script:LogFile -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) -ErrorAction SilentlyContinue } catch {}
}
function Write-Step { param([string]$Text) Write-Line ''; Write-Line ("==> " + $Text) 'Cyan' }
function Write-Ok   { param([string]$Text) Write-Line ("    [OK] " + $Text) 'Green' }
function Write-Note { param([string]$Text) Write-Line ("    [--] " + $Text) 'Gray' }
function Write-Warn { param([string]$Text) Write-Line ("    [!] " + $Text) 'Yellow' }
function Write-Bad  { param([string]$Text) Write-Line ("    [X] " + $Text) 'Red' }

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function ConvertTo-Plain {
    param([Security.SecureString]$Secure)
    if (-not $Secure) { return '' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Test-PortOpen {
    param([int]$Port, [int]$TimeoutMs = 1000)
    $client = $null
    try {
        $client = New-Object Net.Sockets.TcpClient
        $async  = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) { return $true }
        return $false
    } catch { return $false }
    finally { if ($client) { try { $client.Close() } catch {} } }
}

function Get-CpuArch {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    if ($arch -match 'ARM64') { return 'ARM64' }
    return 'AMD64'
}

function Get-SunshineExe {
    $paths = New-Object System.Collections.Generic.List[string]
    if ($env:ProgramFiles) { $paths.Add((Join-Path $env:ProgramFiles 'Sunshine\sunshine.exe')) }
    if (${env:ProgramFiles(x86)}) { $paths.Add((Join-Path ${env:ProgramFiles(x86)} 'Sunshine\sunshine.exe')) }

    try {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($script:ServiceName)'" -ErrorAction SilentlyContinue
        if ($svc -and $svc.PathName) {
            $imagePath = ($svc.PathName -replace '"', '').Trim()
            $dir = Split-Path -Parent $imagePath
            if ($dir) { $paths.Add((Join-Path $dir 'sunshine.exe')) }
        }
    } catch {}

    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*Sunshine*' -and $_.InstallLocation } |
                ForEach-Object { $paths.Add((Join-Path $_.InstallLocation 'sunshine.exe')) }
        } catch {}
    }

    foreach ($p in $paths) {
        if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}

function Invoke-Download {
    param([string]$Url, [string]$OutFile)
    Write-Note "Tai: $Url"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 900
    } catch {
        Write-Warn "Invoke-WebRequest loi: $($_.Exception.Message). Thu lai bang WebClient..."
        try { (New-Object Net.WebClient).DownloadFile($Url, $OutFile) }
        catch { Write-Bad "Tai that bai: $($_.Exception.Message)"; return $false }
    }
    if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 1MB)) {
        $mb = [math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB, 1)
        Write-Note ("Da tai xong (" + $mb + " MB)")
        return $true
    }
    Write-Bad 'File tai ve khong hop le (qua nho).'
    return $false
}

function Wait-ForSunshineExe {
    param([int]$TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $exe = Get-SunshineExe
        if ($exe) { return $exe }
        Start-Sleep -Seconds 3
    }
    return $null
}

# ---------------------------------------------------------------- Cai Sunshine --
function Install-Sunshine {
    $arch    = Get-CpuArch
    $baseUrl = 'https://github.com/LizardByte/Sunshine/releases/latest/download'
    $tmpDir  = Join-Path $env:TEMP ('sunshine-setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    Write-Note "Kien truc CPU: $arch | Thu muc tam: $tmpDir"

    # --- Cach 1: MSI (LizardByte khuyen nghi, cai im lang on dinh nhat) ---
    $msiPath = Join-Path $tmpDir "Sunshine-Windows-$arch-installer.msi"
    if (Invoke-Download "$baseUrl/Sunshine-Windows-$arch-installer.msi" $msiPath) {
        Write-Note 'Cai dat im lang bang msiexec /qn ...'
        $msiLog  = Join-Path $tmpDir 'msi-install.log'
        $msiArgs = @('/i', ('"' + $msiPath + '"'), '/qn', '/norestart', '/L*v', ('"' + $msiLog + '"'))
        try {
            $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -PassThru
            $proc.WaitForExit()
            $code = $proc.ExitCode
            Write-Note "msiexec ket thuc voi ma: $code"
            if (@(0, 1641, 3010) -contains $code) {
                $exe = Wait-ForSunshineExe -TimeoutSec 60
                if ($exe) { Write-Ok "Da cai Sunshine (MSI): $exe"; return $exe }
            }
        } catch { Write-Warn "msiexec loi: $($_.Exception.Message)" }
        Write-Warn 'Cai bang MSI khong thanh cong, chuyen sang ban EXE...'
    }

    # --- Cach 2: EXE cai im lang ---
    $exePath = Join-Path $tmpDir "Sunshine-Windows-$arch-installer.exe"
    if (Invoke-Download "$baseUrl/Sunshine-Windows-$arch-installer.exe" $exePath) {
        $argSets = New-Object System.Collections.Generic.List[object]
        $argSets.Add(@('/S'))
        $argSets.Add(@('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'))
        foreach ($silentArgs in $argSets) {
            Write-Note ("Chay installer voi tham so: " + ($silentArgs -join ' '))
            try {
                $proc = Start-Process -FilePath $exePath -ArgumentList $silentArgs -PassThru
                $proc.WaitForExit()
                Write-Note "Installer ket thuc voi ma: $($proc.ExitCode)"
            } catch { Write-Warn "Loi khi chay installer: $($_.Exception.Message)" }

            $exe = Wait-ForSunshineExe -TimeoutSec 60
            if ($exe) { Write-Ok "Da cai Sunshine (EXE): $exe"; return $exe }
        }

        # --- Cach 3: mo installer o che do thu cong ---
        Write-Warn 'Cai im lang that bai. Mo installer de ban bam Next -> Install thu cong...'
        try {
            $proc = Start-Process -FilePath $exePath -PassThru
            $proc.WaitForExit()
        } catch { Write-Bad "Khong mo duoc installer: $($_.Exception.Message)" }
        $exe = Wait-ForSunshineExe -TimeoutSec 30
        if ($exe) { Write-Ok "Da cai Sunshine: $exe"; return $exe }
    }

    return $null
}

# ---------------------------------------------------------- Am thanh Windows --
function Enable-AudioServices {
    # Tuong duong voi:
    #   sc config AudioEndpointBuilder start= auto  +  net start AudioEndpointBuilder
    #   sc config Audiosrv             start= auto  +  net start Audiosrv
    $audioServices = @(
        @{ Name = 'AudioEndpointBuilder'; Label = 'Windows Audio Endpoint Builder' },
        @{ Name = 'Audiosrv';             Label = 'Windows Audio' }
    )

    foreach ($item in $audioServices) {
        $name = $item.Name

        # 1) sc config <ten> start= auto
        try {
            $cfgArgs = @('config', $name, 'start=', 'auto')
            & sc.exe @cfgArgs | Out-Null
        } catch { Write-Warn "sc config $name loi: $($_.Exception.Message)" }
        try { Set-Service -Name $name -StartupType Automatic -ErrorAction SilentlyContinue } catch {}

        # 2) net start <ten>
        $status = 'Unknown'
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            if ($svc.Status -ne 'Running') {
                try { Start-Service -Name $name -ErrorAction Stop }
                catch { try { & net.exe start $name | Out-Null } catch {} }
                Start-Sleep -Seconds 2
                $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            }
            if ($svc) { $status = [string]$svc.Status }
        } catch {
            Write-Warn "Khong tim thay dich vu $name tren may nay."
            continue
        }

        if ($status -eq 'Running') { Write-Ok "$($item.Label) [$name]: dang chay, startup = Automatic." }
        else { Write-Warn "$($item.Label) [$name]: trang thai '$status'. Kiem tra lai trong services.msc." }
    }

    # Liet ke thiet bi am thanh (VPS thuong khong co card am thanh that)
    try {
        $devices = Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction SilentlyContinue
        if ($devices) {
            foreach ($d in $devices) { Write-Note ('Thiet bi am thanh: ' + $d.Name + ' [' + $d.Status + ']') }
        } else {
            Write-Note 'Khong co card am thanh vat ly (binh thuong voi VPS) -> se cai virtual audio driver ngay sau day.'
        }
    } catch {}
}

# ------------------------------------------------- Virtual audio (VB-CABLE) --
function Get-AudioRenderNames {
    # Liet ke cac thiet bi PHAT am thanh dang Active (doc tu registry MMDevices)
    $names = New-Object System.Collections.Generic.List[string]
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    if (-not (Test-Path -LiteralPath $base)) { return $names }

    foreach ($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
        $state = $null
        try { $state = (Get-ItemProperty -LiteralPath $key.PSPath -Name 'DeviceState' -ErrorAction Stop).DeviceState } catch {}
        if ($state -ne 1) { continue }

        $friendly = $null
        $propPath = $key.PSPath + '\Properties'
        foreach ($prop in @('{b3f8fa53-0004-438e-9003-51a46e139bfc},6', '{a45c254e-df1c-4efd-8020-67d146a850e0},2')) {
            if ($friendly) { continue }
            try { $friendly = (Get-ItemProperty -LiteralPath $propPath -Name $prop -ErrorAction Stop).$prop } catch {}
        }
        if ($friendly) { $names.Add([string]$friendly) }
    }
    return $names
}

function Get-SunshineAudioDevices {
    # Doc danh sach thiet bi bang tools\audio-info.exe cua Sunshine
    $devices = New-Object System.Collections.Generic.List[object]
    $exe = Get-SunshineExe
    if (-not $exe) { return $devices }
    $tool = Join-Path (Split-Path -Parent $exe) 'tools\audio-info.exe'
    if (-not (Test-Path -LiteralPath $tool)) { return $devices }

    $lines = @()
    try { $lines = & $tool 2>&1 } catch { return $devices }
    $current = $null
    foreach ($raw in $lines) {
        $line = [string]$raw
        if ($line -match '^\s*Device name\s*:\s*(.+?)\s*$') {
            $current = [pscustomobject]@{ Name = $Matches[1]; State = '' }
            $devices.Add($current)
        } elseif ($line -match '^\s*Device state\s*:\s*(.+?)\s*$') {
            if ($current) { $current.State = $Matches[1] }
        }
    }
    return $devices
}

function Add-DriverCertificate {
    param([string]$Folder)
    # Tin cay chung chi cua driver -> Windows khong hien popup "Would you like to install..."
    $cats = @(Get-ChildItem -LiteralPath $Folder -Filter '*.cat' -Recurse -ErrorAction SilentlyContinue)
    if ($cats.Count -eq 0) { return }
    $added = 0
    foreach ($cat in $cats) {
        $cert = $null
        try { $cert = (Get-AuthenticodeSignature -FilePath $cat.FullName -ErrorAction Stop).SignerCertificate } catch {}
        if (-not $cert) { continue }
        foreach ($storeName in @('TrustedPublisher', 'Root')) {
            try {
                $store = New-Object Security.Cryptography.X509Certificates.X509Store($storeName, 'LocalMachine')
                $store.Open('ReadWrite')
                $store.Add($cert)
                $store.Close()
                $added++
            } catch {}
        }
    }
    if ($added -gt 0) { Write-Note 'Da tin cay chung chi driver VB-Audio (khong can bam xac nhan khi cai).' }
}

function Wait-ForAudioDevice {
    param([int]$TimeoutSec = 45, [int]$BaselineCount = 0)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ($true) {
        $names = @(Get-AudioRenderNames)
        if (@($names -match $script:VirtualAudioRe).Count -gt 0) { return $true }
        if ($names.Count -gt $BaselineCount) { return $true }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Install-VbCable {
    param([int]$BaselineCount = 0)
    $work = Join-Path $env:ProgramData 'sunshine-setup\vbcable'
    $done = $false
    try {
        try {
            if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $work -Force | Out-Null
        } catch { Write-Warn 'Khong tao duoc thu muc tam cho driver.'; return $false }

        $zip = Join-Path $work 'VBCABLE_Driver_Pack.zip'
        Write-Note ('Tai VB-CABLE: ' + $script:VbCableUrl)
        try {
            Invoke-WebRequest -Uri $script:VbCableUrl -OutFile $zip -UseBasicParsing -TimeoutSec 600
        } catch {
            try { (New-Object Net.WebClient).DownloadFile($script:VbCableUrl, $zip) }
            catch { Write-Warn ('Tai VB-CABLE that bai: ' + $_.Exception.Message); return $false }
        }
        if (-not (Test-Path -LiteralPath $zip) -or (Get-Item -LiteralPath $zip).Length -lt 200KB) {
            Write-Warn 'File VB-CABLE tai ve khong hop le.'
            return $false
        }

        try { Expand-Archive -LiteralPath $zip -DestinationPath $work -Force }
        catch { Write-Warn ('Khong giai nen duoc VB-CABLE: ' + $_.Exception.Message); return $false }

        Add-DriverCertificate -Folder $work

        $setupName = 'VBCABLE_Setup_x64.exe'
        if ([IntPtr]::Size -eq 4) { $setupName = 'VBCABLE_Setup.exe' }
        $setup = @(Get-ChildItem -LiteralPath $work -Filter $setupName -Recurse -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($setup) {
            Write-Note ('Cai im lang: ' + $setup.Name + ' -i -h')
            try {
                $proc = Start-Process -FilePath $setup.FullName -ArgumentList '-i', '-h' -PassThru -ErrorAction Stop
                if (-not $proc.WaitForExit(300000)) { try { $proc.Kill() } catch {} }
            } catch { Write-Warn ('Chay VBCABLE_Setup that bai: ' + $_.Exception.Message) }
        } else {
            Write-Warn ('Khong tim thay ' + $setupName + ' trong goi driver.')
        }

        $done = Wait-ForAudioDevice -TimeoutSec 45 -BaselineCount $BaselineCount
        if (-not $done) {
            # Du phong: cai thang tu file .inf
            $inf = @(Get-ChildItem -LiteralPath $work -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '64' }) | Select-Object -First 1
            if (-not $inf) { $inf = @(Get-ChildItem -LiteralPath $work -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue) | Select-Object -First 1 }
            if ($inf) {
                Write-Note ('Thu cai tu file INF: ' + $inf.Name)
                try {
                    $pnpArgs = @('/add-driver', $inf.FullName, '/install')
                    & pnputil.exe @pnpArgs | Out-Null
                } catch {}
                try {
                    $dllArgs = @('advpack.dll,LaunchINFSectionEx', ($inf.FullName + ',,,4'))
                    & rundll32.exe @dllArgs | Out-Null
                } catch {}
                $done = Wait-ForAudioDevice -TimeoutSec 45 -BaselineCount $BaselineCount
            }
        }
    } finally {
        try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    return $done
}

function Set-SunshineAudioSink {
    # Ghi audio_sink vao sunshine.conf de Sunshine lay dung thiet bi ao
    $exe = Get-SunshineExe
    if (-not $exe) { return }

    $pick = $null
    foreach ($d in @(Get-SunshineAudioDevices)) {
        if ([string]$d.Name -match $script:VirtualAudioRe) { $pick = [string]$d.Name; break }
    }
    if (-not $pick) {
        Write-Note 'Chua doc duoc ten thiet bi tu audio-info.exe -> de Sunshine tu chon thiet bi mac dinh.'
        return
    }

    $conf    = Join-Path (Split-Path -Parent $exe) 'config\sunshine.conf'
    $confDir = Split-Path -Parent $conf
    try { if (-not (Test-Path -LiteralPath $confDir)) { New-Item -ItemType Directory -Path $confDir -Force | Out-Null } } catch {}

    $kept = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $conf) {
        $old = @()
        try { $old = @(Get-Content -LiteralPath $conf -ErrorAction Stop) } catch {}
        foreach ($line in $old) {
            if ([string]$line -match '^\s*audio_sink\s*=') { continue }
            $kept.Add([string]$line)
        }
    }
    $kept.Add('audio_sink = ' + $pick)

    try { [IO.File]::WriteAllLines($conf, $kept) }
    catch { Write-Warn ('Khong ghi duoc sunshine.conf: ' + $_.Exception.Message); return }
    Write-Ok ('Da dat audio_sink = ' + $pick)

    try {
        $svc = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Restart-Service -Name $script:ServiceName -Force -ErrorAction SilentlyContinue
            Write-Note 'Da restart SunshineService de nap cau hinh am thanh.'
        }
    } catch {}
}

function Install-VirtualAudio {
    if ($SkipVirtualAudio) {
        Write-Note 'Bo qua virtual audio driver (-SkipVirtualAudio).'
        return
    }

    $existing   = @(Get-AudioRenderNames)
    $hasVirtual = @($existing -match $script:VirtualAudioRe).Count -gt 0

    if ($existing.Count -gt 0 -and -not $ForceVirtualAudio) {
        Write-Ok ('Thiet bi phat am thanh dang hoat dong: ' + ($existing -join ' | '))
        if ($hasVirtual) { Set-SunshineAudioSink }
        else { Write-Note 'Muon cai them VB-CABLE thi chay lai script voi -ForceVirtualAudio.' }
        return
    }

    Write-Note 'May khong co dau ra am thanh -> cai VB-CABLE (VB-Audio Virtual Cable).'
    if (Install-VbCable -BaselineCount $existing.Count) {
        $names = @(Get-AudioRenderNames)
        if ($names.Count -gt 0) { Write-Ok ('Thiet bi am thanh hien co: ' + ($names -join ' | ')) }
        else { Write-Ok 'Da cai virtual audio driver.' }
        Set-SunshineAudioSink
    } else {
        Write-Warn 'Chua thay thiet bi am thanh ao. Thu reboot VPS roi chay lai script.'
        Write-Warn 'Hoac cai tay: https://vb-audio.com/Cable/ -> giai nen -> VBCABLE_Setup_x64.exe -> Install Driver.'
    }
}

# ------------------------------------------------------------------- Service --
function Start-SunshineService {
    $svc = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Warn "Khong thay service $($script:ServiceName). Sunshine co the dang chay o che do ung dung."
        return $false
    }
    try { Set-Service -Name $script:ServiceName -StartupType Automatic } catch { Write-Warn "Khong dat duoc Automatic: $($_.Exception.Message)" }
    try {
        if ($svc.Status -ne 'Running') { Start-Service -Name $script:ServiceName }
        else { Restart-Service -Name $script:ServiceName -Force }
    } catch { Write-Warn "Khong start duoc service: $($_.Exception.Message)" }

    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (Test-PortOpen -Port $script:WebUiPort) {
            Write-Ok "Sunshine dang lang nghe tai port $($script:WebUiPort)."
            return $true
        }
        Start-Sleep -Seconds 2
    }
    Write-Warn "Chua thay port $($script:WebUiPort) mo. Neu VPS chua co phien dang nhap (session) thi Sunshine se chua khoi dong duoc."
    return $false
}

# ------------------------------------------------------------------ Firewall --
function Set-SunshineFirewall {
    param([switch]$KeepEnabled)

    $tcpList = ($script:TcpPorts -join ',')
    $udpList = ($script:UdpPorts -join ',')

    $rules = @(
        @{ Name = 'Sunshine TCP In';  Protocol = 'TCP'; Ports = $script:TcpPorts; PortText = $tcpList },
        @{ Name = 'Sunshine UDP In';  Protocol = 'UDP'; Ports = $script:UdpPorts; PortText = $udpList }
    )

    foreach ($rule in $rules) {
        $added = $false
        try {
            Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow `
                -Protocol $rule.Protocol -LocalPort $rule.Ports -Profile Any -ErrorAction Stop | Out-Null
            $added = $true
        } catch {
            try {
                $delArgs = @('advfirewall', 'firewall', 'delete', 'rule', ('name=' + $rule.Name))
                $addArgs = @('advfirewall', 'firewall', 'add', 'rule', ('name=' + $rule.Name),
                             'dir=in', 'action=allow', ('protocol=' + $rule.Protocol), ('localport=' + $rule.PortText))
                & netsh.exe @delArgs | Out-Null
                & netsh.exe @addArgs | Out-Null
                $added = $true
            } catch { Write-Warn "Khong tao duoc rule $($rule.Name): $($_.Exception.Message)" }
        }
        if ($added) { Write-Ok "Rule '$($rule.Name)': $($rule.Protocol) $($rule.PortText)" }
    }

    if ($KeepEnabled) {
        Write-Note 'Giu nguyen Windows Firewall (chi them rule) vi ban dung -KeepFirewall.'
        return
    }

    try {
        Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled False -ErrorAction Stop
        Write-Ok 'Da TAT Windows Firewall (ca 3 profile: Domain / Private / Public).'
    } catch {
        try {
            & netsh.exe advfirewall set allprofiles state off | Out-Null
            Write-Ok 'Da TAT Windows Firewall bang netsh.'
        } catch { Write-Bad "Khong tat duoc firewall: $($_.Exception.Message)" }
    }
    Write-Warn 'Firewall dang TAT: may nay mo hoan toan ra Internet. Nen dat mat khau manh va bat lai firewall khi khong dung.'
}

# ------------------------------------------------------------------ Dia chi IP --
function Get-LocalIPv4 {
    $ips = @()
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -ExpandProperty IPAddress
    } catch {
        try {
            $ips = [Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                ForEach-Object { $_.IPAddressToString } |
                Where-Object { $_ -notlike '127.*' -and $_ -notlike '169.254.*' }
        } catch {}
    }
    return @($ips | Sort-Object -Unique)
}

function Get-PublicIPv4 {
    foreach ($url in @('https://api.ipify.org', 'https://ifconfig.me/ip', 'https://icanhazip.com', 'http://checkip.amazonaws.com')) {
        try {
            $resp = Invoke-RestMethod -Uri $url -TimeoutSec 10
            $ip   = ($resp | Out-String).Trim()
            if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') { return $ip }
        } catch {}
    }
    return $null
}

# -------------------------------------------------------------- Mat khau may --
function Get-DesiredPassword {
    param([string]$Provided, [switch]$ForceDefault)

    if ($Provided)    { Write-Note 'Dung mat khau truyen tu tham so/bien moi truong.'; return $Provided }
    if ($ForceDefault) { Write-Note 'Dung mat khau mac dinh.'; return $script:DefaultPassword }

    Write-Line "    Mat khau mac dinh: $($script:DefaultPassword)" 'White'
    Write-Line '    Nhan Enter de dung mat khau mac dinh, hoac nhap mat khau moi cua ban.' 'White'

    for ($i = 1; $i -le 3; $i++) {
        try   { $first = Read-Host -Prompt '    Mat khau moi' -AsSecureString }
        catch { Write-Warn 'Khong nhap duoc tu ban phim (che do khong tuong tac). Dung mat khau mac dinh.'; return $script:DefaultPassword }

        $plain1 = ConvertTo-Plain $first
        if ([string]::IsNullOrEmpty($plain1)) {
            Write-Note 'Da chon mat khau mac dinh.'
            return $script:DefaultPassword
        }

        $second = Read-Host -Prompt '    Nhap lai mat khau de xac nhan' -AsSecureString
        $plain2 = ConvertTo-Plain $second

        if ($plain1 -ceq $plain2) {
            if ($plain1.Length -lt 8) { Write-Warn 'Mat khau ngan hon 8 ky tu, Windows co the tu choi vi chinh sach do phuc tap.' }
            Write-Ok 'Hai lan nhap trung khop.'
            return $plain1
        }
        Write-Bad "Hai lan nhap KHONG giong nhau. Thu lai ($i/3)."
    }

    Write-Warn 'Nhap sai 3 lan. Dung mat khau mac dinh.'
    return $script:DefaultPassword
}

function Set-WindowsPassword {
    param([string]$UserName, [string]$Plain)

    if (-not $UserName) { $UserName = $env:USERNAME }
    Write-Note "Tai khoan se doi mat khau: $UserName"

    try {
        $secure = ConvertTo-SecureString $Plain -AsPlainText -Force
        Get-LocalUser -Name $UserName -ErrorAction Stop | Out-Null
        Set-LocalUser -Name $UserName -Password $secure -PasswordNeverExpires $true -ErrorAction Stop
        try { Enable-LocalUser -Name $UserName -ErrorAction SilentlyContinue } catch {}
        Write-Ok "Da doi mat khau Windows cho '$UserName'."
        return $true
    } catch {
        Write-Warn "Set-LocalUser khong dung duoc ($($_.Exception.Message)). Thu bang net.exe user..."
    }

    try {
        $out = & net.exe user $UserName $Plain 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Da doi mat khau Windows cho '$UserName' (net user)."
            try { & net.exe accounts /maxpwage:unlimited | Out-Null } catch {}
            return $true
        }
        Write-Bad ('net user loi: ' + (($out | Out-String).Trim()))
    } catch { Write-Bad "Khong doi duoc mat khau: $($_.Exception.Message)" }

    return $false
}

# ------------------------------------------------------- Mat khau Web UI Sunshine --
function Set-SunshineWebCreds {
    param([string]$Exe, [string]$UserName, [string]$Plain)

    if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) { return $false }

    $svc = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
    $wasRunning = ($svc -and $svc.Status -eq 'Running')
    if ($wasRunning) { try { Stop-Service -Name $script:ServiceName -Force; Start-Sleep -Seconds 2 } catch {} }

    $ok = $false
    try {
        $credArgs = @('--creds', ('"' + $UserName + '"'), ('"' + $Plain + '"'))
        $proc = Start-Process -FilePath $Exe -ArgumentList $credArgs -NoNewWindow -PassThru
        if (-not $proc.WaitForExit(30000)) { try { $proc.Kill() } catch {} }
        $ok = $true
        Write-Ok "Da dat dang nhap Web UI Sunshine: user '$UserName'."
    } catch { Write-Warn "Khong dat duoc user/pass Web UI tu dong: $($_.Exception.Message). Ban co the tao truc tiep tren trang web." }

    if ($wasRunning -or $svc) {
        try { Start-Service -Name $script:ServiceName -ErrorAction SilentlyContinue } catch {}
    }
    return $ok
}

# ------------------------------------------------------------------- Trinh duyet --
function Open-WebUi {
    param([string]$Url)
    $attempts = @(
        { Start-Process $Url },
        { Start-Process 'msedge.exe' $Url },
        { Start-Process 'chrome.exe' $Url },
        { Start-Process 'cmd.exe' ('/c start "" "' + $Url + '"') }
    )
    foreach ($attempt in $attempts) {
        try { & $attempt; Write-Ok "Da mo $Url tren trinh duyet."; return $true } catch {}
    }
    Write-Warn "Khong mo duoc trinh duyet tu dong. Hay mo tay: $Url"
    return $false
}

# ------------------------------------------------------------------------ Main --
function Invoke-SunshineSetup {
    Write-Line ''
    Write-Line '################################################################' 'Cyan'
    Write-Line '#          SUNSHINE VPS AUTO SETUP  (Windows PowerShell)        #' 'Cyan'
    Write-Line '################################################################' 'Cyan'
    Write-Note "Log: $($script:LogFile)"

    # 1. Quyen Administrator
    Write-Step 'Buoc 1/8: Kiem tra quyen Administrator'
    if (-not (Test-IsAdmin)) {
        Write-Bad 'Script CAN quyen Administrator.'
        Write-Line '    Hay mo Start -> go "PowerShell" -> chuot phai -> Run as administrator, roi chay lai lenh.' 'Yellow'
        return
    }
    Write-Ok "Dang chay voi quyen admin ($env:USERDOMAIN\$env:USERNAME)."

    # 2. Cai Sunshine
    Write-Step 'Buoc 2/8: Cai dat Sunshine'
    $exe = Get-SunshineExe
    if ($exe -and -not $Force) {
        Write-Ok "Sunshine da co san: $exe (dung -Force de cai lai)"
    } else {
        $exe = Install-Sunshine
        if (-not $exe) {
            Write-Bad 'Khong cai duoc Sunshine. Kiem tra ket noi mang cua VPS roi chay lai script.'
            return
        }
    }

    # 3. Am thanh Windows + virtual audio driver
    Write-Step 'Buoc 3/8: Bat am thanh Windows + cai virtual audio driver'
    Enable-AudioServices
    Install-VirtualAudio

    # 4. Service
    Write-Step 'Buoc 4/8: Bat service Sunshine (tu dong chay cung Windows)'
    $serviceUp = Start-SunshineService

    # 5. Firewall
    Write-Step 'Buoc 5/8: Mo port + tat Windows Firewall'
    if ($KeepFirewall) { Set-SunshineFirewall -KeepEnabled } else { Set-SunshineFirewall }

    # 6. Mat khau Windows
    Write-Step 'Buoc 6/8: Dat mat khau tai khoan Windows'
    $targetUser   = if ($User) { $User } else { $env:USERNAME }
    $finalPassword = $null
    if ($SkipPassword) {
        Write-Note 'Bo qua buoc doi mat khau (-SkipPassword).'
    } else {
        $finalPassword = Get-DesiredPassword -Provided $Password -ForceDefault:$UseDefaultPassword
        if (-not (Set-WindowsPassword -UserName $targetUser -Plain $finalPassword)) {
            Write-Warn 'Khong doi duoc mat khau Windows. Mat khau cu van giu nguyen.'
        }
    }

    # 7. Web UI creds + mo trinh duyet
    Write-Step 'Buoc 7/8: Cau hinh Web UI Sunshine'
    $webPassword = $null
    if (-not $SkipWebUiCreds) {
        $webPassword = if ($finalPassword) { $finalPassword } else { $script:DefaultPassword }
        if (-not (Set-SunshineWebCreds -Exe $exe -UserName $WebUiUser -Plain $webPassword)) { $webPassword = $null }
    } else {
        Write-Note 'Bo qua dat user/pass Web UI (-SkipWebUiCreds).'
    }

    $localUrl = "https://localhost:$($script:WebUiPort)"
    if (-not $serviceUp) {
        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline -and -not (Test-PortOpen -Port $script:WebUiPort)) { Start-Sleep -Seconds 2 }
    }
    if ($NoBrowser) { Write-Note 'Bo qua mo trinh duyet (-NoBrowser).' } else { Open-WebUi -Url $localUrl | Out-Null }

    # 8. Tong ket + IP
    Write-Step 'Buoc 8/8: Thong tin ket noi'
    $localIps = Get-LocalIPv4
    $publicIp = Get-PublicIPv4
    $mainIp   = if ($publicIp) { $publicIp } elseif ($localIps.Count -gt 0) { $localIps[0] } else { 'IP_CUA_VPS' }
    $publicIpText = if ($publicIp) { $publicIp } else { 'khong xac dinh duoc' }
    $localIpText  = if ($localIps.Count -gt 0) { ($localIps -join ', ') } else { 'khong xac dinh duoc' }

    Write-Line ''
    Write-Line '================================================================' 'Green'
    Write-Line '                  HOAN TAT - THONG TIN TRUY CAP                 ' 'Green'
    Write-Line '================================================================' 'Green'
    Write-Line "  IPv4 public (dung tu ben ngoai) : $publicIpText" 'White'
    Write-Line "  IPv4 noi bo cua may             : $localIpText" 'White'
    Write-Line ''
    Write-Line "  Web UI tren may nay             : $localUrl" 'White'
    Write-Line "  Web UI tu may khac              : https://${mainIp}:$($script:WebUiPort)" 'White'
    Write-Line "  Dia chi nhap vao Moonlight      : $mainIp" 'White'
    Write-Line ''
    Write-Line "  Tai khoan Windows               : $targetUser" 'White'
    if ($finalPassword) { Write-Line "  Mat khau Windows                : $finalPassword" 'Yellow' }
    else                { Write-Line '  Mat khau Windows                : (khong doi)' 'Gray' }
    if ($webPassword)   { Write-Line "  Web UI Sunshine                 : $WebUiUser / $webPassword" 'Yellow' }
    else                { Write-Line '  Web UI Sunshine                 : tu tao user/pass o lan mo dau tien' 'Gray' }
    Write-Line '================================================================' 'Green'
    Write-Line ''
    Write-Line '  Ghi chu quan trong:' 'Cyan'
    Write-Line '   1. Trinh duyet se canh bao "khong an toan" vi Sunshine dung SSL tu ky -> chon Advanced / Continue.' 'Gray'
    Write-Line '   2. Neu VPS o Azure / AWS / GCP: phai mo them port trong Security Group / NSG cua nha cung cap' 'Gray'
    Write-Line "      TCP $($script:TcpPorts -join ', ') va UDP $($script:UdpPorts -join ', ')" 'Gray'
    Write-Line '   3. Sunshine can mot phien man hinh dang mo. Tren VPS nen cai virtual display driver' 'Gray'
    Write-Line '      va giu phien dang nhap (vi du dung: tscon 1 /dest:console) truoc khi ngat RDP.' 'Gray'
    Write-Line '   4. Ghep doi Moonlight: mo Web UI -> tab PIN -> nhap PIN ma Moonlight hien ra.' 'Gray'
    Write-Line '   5. Bat lai firewall khi can: Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True' 'Gray'
    Write-Line '   6. Am thanh: da bat Audiosrv + AudioEndpointBuilder va cai VB-CABLE khi may khong co card am thanh.' 'Gray'
    Write-Line '      Xem thiet bi: & "$env:ProgramFiles\Sunshine\tools\audio-info.exe" - doi thiet bi o Web UI > Audio/Video.' 'Gray'
    Write-Line ''
}

try {
    Invoke-SunshineSetup
} catch {
    Write-Bad "Loi khong mong doi: $($_.Exception.Message)"
    Write-Line ($_.ScriptStackTrace) 'DarkGray'
}
