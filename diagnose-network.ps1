$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

$you = New-Object System.Collections.Generic.List[string]
$ok = New-Object System.Collections.Generic.List[string]

function Write-Title([string]$text) {
    Write-Host ""
    Write-Host ("=== {0} ===" -f $text) -ForegroundColor Cyan
}

function Test-DummyNic([string]$alias) {
    $a = ([string]$alias).ToLower()
    if ($a -match "vethernet|default switch|hyper-v|wsl|loopback|bluetooth|virtualbox|vmware|outline|tap|tun|vpn|radmin|hamachi|zerotier|tailscale") {
        return $true
    }
    return $false
}

function Test-CGNAT([string]$ip) {
    if (-not $ip) { return $false }
    $p = $ip.Split(".")
    if ($p.Count -ne 4) { return $false }
    $a = [int]$p[0]
    $b = [int]$p[1]
    if ($a -eq 100 -and $b -ge 64 -and $b -le 127) { return $true }
    if ($a -eq 10) { return $true }
    if ($a -eq 192 -and $b -eq 168) { return $true }
    if ($a -eq 172 -and $b -ge 16 -and $b -le 31) { return $true }
    return $false
}

function Get-LanIPv4 {
    $list = @()
    try {
        $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown" }
        foreach ($a in $addrs) {
            $list += [pscustomobject]@{
                IP      = $a.IPAddress
                IfIndex = $a.InterfaceIndex
                Alias   = $a.InterfaceAlias
            }
        }
    }
    catch {
        foreach ($line in (ipconfig)) {
            if ($line -match "IPv4[^:]*:\s*([0-9.]+)") {
                $ip = $Matches[1]
                if ($ip -ne "127.0.0.1") {
                    $list += [pscustomobject]@{ IP = $ip; IfIndex = 0; Alias = "" }
                }
            }
        }
    }
    return $list
}

function Get-PublicIP {
    foreach ($url in @("https://api.ipify.org", "https://icanhazip.com", "https://ifconfig.me/ip")) {
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 8
            $ip = ($r.Content).Trim()
            if ($ip -match "^\d{1,3}(\.\d{1,3}){3}$") { return $ip }
        }
        catch { }
    }
    return ""
}

function Get-UdpListen([int]$port) {
    $hits = @()
    try {
        $hits = @(Get-NetUDPEndpoint -LocalPort $port -ErrorAction Stop)
    }
    catch {
        foreach ($line in (netstat -ano -p UDP)) {
            if ($line -match ":$port\s" -or $line -match ":$port$") {
                $hits += $line
            }
        }
    }
    return $hits
}

function Test-FirewallUdp([int]$port) {
    $names = @()
    try {
        $rules = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -ErrorAction Stop
        foreach ($rule in $rules) {
            $ports = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
            foreach ($p in @($ports)) {
                if ($p.Protocol -ne "UDP" -and $p.Protocol -ne "Any") { continue }
                $lp = [string]$p.LocalPort
                $name = [string]$rule.DisplayName
                $exact = $lp -eq "$port" -or $lp -match "(^|,)$port(,|$)"
                $ours = $name -match "DEEPER|unitates|Unitates"
                if ($exact -or $ours) { $names += $name }
            }
        }
    }
    catch { }
    return $names | Select-Object -Unique
}

Write-Host "UNITATES  //  diagnostika seti hosta"
Write-Host "Zapuskai na PK gde start-server.bat. Drugu etot fail ne nuzhen."
Write-Host ""

Write-Title "LOKALNYE IP"
$lans = @(Get-LanIPv4)
$lanPreferred = ""
if ($lans.Count -eq 0) {
    Write-Host "IPv4 net." -ForegroundColor Red
    $you.Add("Na etom PK net IPv4. Net Wi-Fi/kabelya ili adapter bez adresa.")
}
else {
    foreach ($lan in $lans) {
        $dummy = Test-DummyNic $lan.Alias
        $mark = ""
        if ($dummy) { $mark = "  [virtual/VPN - drugu ne slat]" }
        elseif ($lan.IP -like "192.168.*" -and -not $lanPreferred) {
            $lanPreferred = $lan.IP
            $mark = "  <- odna Wi-Fi: drug pishet ETO"
        }
        Write-Host ("  {0}  {1}{2}" -f $lan.IP, $lan.Alias, $mark)
    }
    if (-not $lanPreferred) {
        foreach ($lan in $lans) {
            if (Test-DummyNic $lan.Alias) { continue }
            if ($lan.IP -like "10.*" -or $lan.IP -like "172.*") { $lanPreferred = $lan.IP; break }
        }
    }
    if (-not $lanPreferred) { $lanPreferred = $lans[0].IP }
    $ok.Add(("Lokalnyi IP est: {0}" -f $lanPreferred))
}

Write-Title "SERVER IGRY  UDP 7777 / 7788"
$proc = Get-Process -Name "Unitates" -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host ("  Unitates.exe zapushen, PID: {0}" -f (($proc | ForEach-Object { $_.Id }) -join ", "))
    $ok.Add("Process Unitates.exe zapushen.")
}
else {
    Write-Host "  Unitates.exe ne naiden." -ForegroundColor Yellow
    $you.Add("Batnik/server ne zapushen. Snachala start-server.bat, potom snova eta diagnostika.")
}

$listen7777 = @(Get-UdpListen 7777)
$listen7788 = @(Get-UdpListen 7788)
if ($listen7777.Count -gt 0) {
    Write-Host "  UDP 7777 SLUSHAET - igrovoi port zhiv." -ForegroundColor Green
    $ok.Add("Etot PK slushaet UDP 7777. Esli drug ne konnectitsya - pakety ne dohodyat: firewall, router ili ne tot IP.")
}
else {
    Write-Host "  UDP 7777 molchit." -ForegroundColor Red
    $you.Add("Port 7777 ne slushaet. Server ne startoval ili zanyat drugim prilozheniem.")
}
if ($listen7788.Count -gt 0) {
    Write-Host "  UDP 7788 SLUSHAET - poisk serverov zhiv." -ForegroundColor Green
}
else {
    Write-Host "  UDP 7788 molchit (poisk v spiske ne budet rabotat)." -ForegroundColor Yellow
}

Write-Title "FIREWALL WINDOWS"
$fw7777 = @(Test-FirewallUdp 7777)
$fw7788 = @(Test-FirewallUdp 7788)
if ($fw7777.Count -gt 0) {
    Write-Host ("  Vhodyashiy UDP 7777 razreshen: {0}" -f ($fw7777 -join "; "))
    $ok.Add("Firewall puskaet vhodyashiy UDP 7777.")
}
else {
    Write-Host "  Net yavnogo razresheniya na vhodyashiy UDP 7777." -ForegroundColor Yellow
    $you.Add("Firewall Windows mozhet rezat vhod. Zapusti etot batnik ot administratora i soglasis otkryt porty.")
}
if ($fw7788.Count -gt 0) {
    Write-Host ("  Vhodyashiy UDP 7788 razreshen: {0}" -f ($fw7788 -join "; "))
}
else {
    Write-Host "  Net yavnogo razresheniya na vhodyashiy UDP 7788."
}

Write-Title "INTERNET / WAN"
$public = Get-PublicIP
if (-not $public) {
    Write-Host "  Vneshniy IP ne poluchen (net seti ili saity proverki nedostupny)." -ForegroundColor Red
    $you.Add("Etot PK ne dostuchalsya do interneta. Snachala pochini set u sebya.")
}
else {
    Write-Host ("  Vneshniy IP: {0}" -f $public)
    if (Test-CGNAT $public) {
        Write-Host "  Eto seryi/CGNAT adres. Iz interneta na tebya nelzya probrosit port." -ForegroundColor Red
        $you.Add(("Provider dal seryi IP ({0}). Igra iz drugogo doma bez VPN (Hamachi/ZeroTier) ili belogo IP ne vzletit." -f $public))
    }
    else {
        Write-Host ("  Belyi IP. Dlya igry iz drugogo doma drug pishet: {0}" -f $public) -ForegroundColor Green
        $ok.Add(("Belyi WAN {0}. Drug iz drugogo doma pishet EGO, ne 192.168." -f $public))
        $you.Add(("Probros UDP 7777 na routere na {0} - eto tvoya storona. Bez nego belyi IP bespolezen." -f $lanPreferred))
    }
}

Write-Title "CHTO SKAZAT DRUGU"
if ($lanPreferred) {
    Write-Host ("  Odna Wi-Fi / kabel:     {0}" -f $lanPreferred)
}
if ($public -and -not (Test-CGNAT $public)) {
    Write-Host ("  Drugoi internet / dom:  {0}" -f $public)
}
Write-Host "  Nelzya: 127.0.0.1 (eto ego sobstvennyi PK)."

Write-Title "VERDICT"
if ($you.Count -gt 0) {
    Write-Host "TVOYA STORONA:" -ForegroundColor Red
    $i = 1
    foreach ($line in $you) {
        Write-Host ("  {0}. {1}" -f $i, $line)
        $i++
    }
}
if ($ok.Count -gt 0) {
    Write-Host "U TEBYA UZHE OK:" -ForegroundColor Green
    foreach ($line in $ok) { Write-Host ("  - {0}" -f $line) }
}

$readyLan = ($listen7777.Count -gt 0) -and $lanPreferred
$readyWan = $readyLan -and $public -and -not (Test-CGNAT $public)
if ($readyLan -and $fw7777.Count -gt 0) {
    Write-Host ""
    Write-Host ("Esli drug v toi zhe seti pishet {0} i tishina -" -f $lanPreferred) -ForegroundColor Yellow
    Write-Host "chasto vinovata izolyaciya klientov na Wi-Fi (router) ili on v drugoi podseti."
}
if ($readyWan) {
    Write-Host ""
    Write-Host ("Esli drug pishet {0} i ne konnectitsya - snachala probros 7777 u tebya." -f $public) -ForegroundColor Yellow
    Write-Host "Probros sdelan, IP vernyi, server slushaet - togda uzhe kopai u druga."
}

if ($fw7777.Count -eq 0 -or $fw7788.Count -eq 0) {
    Write-Host ""
    $answer = Read-Host "Otkryt vhodyashiy UDP 7777 i 7788 v firewalle? (y/n)"
    if ($answer -eq "y" -or $answer -eq "Y" -or $answer -eq "d" -or $answer -eq "D") {
        $exe = Join-Path $PSScriptRoot "Unitates.exe"
        $prog = ""
        if (Test-Path $exe) { $prog = " program=`"$exe`"" }
        foreach ($port in @(7777, 7788)) {
            $name = "DEEPER UDP $port"
            cmd /c ("netsh advfirewall firewall delete rule name=`"{0}`" >nul 2>nul" -f $name)
            $out = cmd /c ("netsh advfirewall firewall add rule name=`"{0}`" dir=in action=allow protocol=UDP localport={1}{2} profile=any" -f $name, $port, $prog)
            Write-Host $out
        }
        Write-Host "Pravila dobavleny. Esli Access denied - zapusti batnik ot administratora."
    }
}

Write-Host ""
Read-Host "Nazhmi Enter"
