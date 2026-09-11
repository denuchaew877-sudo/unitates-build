$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

function Get-HomeLan {
    $best = ""
    try {
        foreach ($a in Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop) {
            if ($a.IPAddress -eq "127.0.0.1") { continue }
            $nic = ([string]$a.InterfaceAlias).ToLower()
            if ($nic -match "vethernet|default switch|hyper-v|wsl|outline|tap|tun|vpn|virtualbox|vmware") { continue }
            if ($a.IPAddress -like "192.168.*") { return $a.IPAddress }
            if (-not $best) { $best = $a.IPAddress }
        }
    }
    catch { }
    return $best
}

function Get-PublicIP {
    foreach ($url in @("https://api.ipify.org", "https://icanhazip.com")) {
        try {
            $ip = (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 8).Content.Trim()
            if ($ip -match "^\d{1,3}(\.\d{1,3}){3}$") { return $ip }
        }
        catch { }
    }
    return ""
}

function Open-Firewall {
    foreach ($port in @(7777, 7788)) {
        $name = "DEEPER UDP $port"
        cmd /c "netsh advfirewall firewall add rule name=`"$name`" dir=in action=allow protocol=UDP localport=$port profile=any" | Out-Null
    }
}

function Try-Upnp([string]$lan) {
    if (-not $lan) { return $false }
    $search = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1`r`n`r`n"
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.Client.ReceiveTimeout = 3000
    $udp.EnableBroadcast = $true
    $bytes = [Text.Encoding]::ASCII.GetBytes($search)
    try { $udp.Send($bytes, $bytes.Length, "239.255.255.250", 1900) | Out-Null } catch { $udp.Close(); return $false }
    $remote = New-Object System.Net.IPEndPoint ([Net.IPAddress]::Any, 0)
    try { $ans = $udp.Receive([ref]$remote) } catch { $udp.Close(); return $false }
    $udp.Close()
    $text = [Text.Encoding]::ASCII.GetString($ans)
    $location = ""
    foreach ($line in $text.Split("`n")) {
        if ($line -match "^LOCATION:\s*(.+)$") { $location = $Matches[1].Trim(); break }
    }
    if (-not $location) { return $false }
    try { $desc = (Invoke-WebRequest -UseBasicParsing -Uri $location -TimeoutSec 5).Content } catch { return $false }
    $service = ""
    $control = ""
    foreach ($short in @("WANIPConnection:1", "WANPPPConnection:1")) {
        $type = "urn:schemas-upnp-org:service:$short"
        $idx = $desc.IndexOf($type, [StringComparison]::OrdinalIgnoreCase)
        if ($idx -lt 0) { continue }
        $u = $desc.IndexOf("<controlURL>", $idx, [StringComparison]::OrdinalIgnoreCase)
        if ($u -lt 0) { continue }
        $s = $u + 12
        $e = $desc.IndexOf("</controlURL>", $s, [StringComparison]::OrdinalIgnoreCase)
        if ($e -lt 0) { continue }
        $path = $desc.Substring($s, $e - $s).Trim()
        $base = [Uri]$location
        $control = if ($path -match "^https?://") { $path } else { ([Uri]::new($base, $path)).ToString() }
        $service = $type
        break
    }
    if (-not $control) { return $false }
    $ok = $false
    foreach ($port in @(7777, 7788)) {
        $inner = "<u:AddPortMapping xmlns:u=`"$service`"><NewRemoteHost></NewRemoteHost><NewExternalPort>$port</NewExternalPort><NewProtocol>UDP</NewProtocol><NewInternalPort>$port</NewInternalPort><NewInternalClient>$lan</NewInternalClient><NewEnabled>1</NewEnabled><NewPortMappingDescription>DEEPER</NewPortMappingDescription><NewLeaseDuration>0</NewLeaseDuration></u:AddPortMapping>"
        $envelope = "<?xml version=`"1.0`"?><s:Envelope xmlns:s=`"http://schemas.xmlsoap.org/soap/envelope/`" s:encodingStyle=`"http://schemas.xmlsoap.org/soap/encoding/`"><s:Body>$inner</s:Body></s:Envelope>"
        try {
            $req = [Net.HttpWebRequest]::Create($control)
            $req.Method = "POST"
            $req.ContentType = "text/xml; charset=`"utf-8`""
            $req.Headers.Add("SOAPACTION", "`"$service#AddPortMapping`"")
            $req.Timeout = 4000
            $data = [Text.Encoding]::UTF8.GetBytes($envelope)
            $req.ContentLength = $data.Length
            $st = $req.GetRequestStream(); $st.Write($data, 0, $data.Length); $st.Close()
            $resp = $req.GetResponse()
            $resp.Close()
            $ok = $true
            Write-Host ("  UPnP UDP {0} -> {1}  OK" -f $port, $lan)
        }
        catch {
            Write-Host ("  UPnP UDP {0}  FAIL: {1}" -f $port, $_.Exception.Message)
        }
    }
    return $ok
}

Write-Host ""
Write-Host "=============================================="
Write-Host "  DRUG IZ DRUGOGO GORODA - NE 192.168 i NE 127"
Write-Host "=============================================="
Write-Host ""

$lan = Get-HomeLan
$wan = Get-PublicIP
Write-Host ("LAN etogo PK:  {0}" -f $(if ($lan) { $lan } else { "???" }))
Write-Host ("WAN / internet: {0}" -f $(if ($wan) { $wan } else { "???" }))
Write-Host ""

Write-Host "Otkryvayu firewall UDP 7777 i 7788..."
Open-Firewall

Write-Host "Proshuy router (UPnP) otkryt UDP 7777 na etot PK..."
$mapped = Try-Upnp $lan
if ($mapped) {
    Write-Host "Router prinial UPnP. OK." -ForegroundColor Green
}
else {
    Write-Host "UPnP skip. Esli v routere uzhe est UDP 7777 -> etot LAN - tak i nado, ne oshibka."
}

Write-Host ""
if ($wan) {
    Write-Host "**********************************************" -ForegroundColor Green
    Write-Host "  DRUG PISHET V PRYAMOE PODKLYUCHENIE:" -ForegroundColor Green
    Write-Host ("           {0}" -f $wan) -ForegroundColor Green
    Write-Host "**********************************************" -ForegroundColor Green
}
else {
    Write-Host "WAN IP ne poluchilsya. Prover internet."
}
Write-Host ""
