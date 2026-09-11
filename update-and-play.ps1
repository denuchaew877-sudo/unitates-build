$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
$env:GIT_TERMINAL_PROMPT = "0"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$OfficialRemote = "https://github.com/denuchaew877-sudo/unitates-build.git"
$OfficialBranch = "main"
$VersionUrls = @(
    "https://cdn.jsdelivr.net/gh/denuchaew877-sudo/unitates-build@main/version.json",
    "https://api.github.com/repos/denuchaew877-sudo/unitates-build/contents/version.json?ref=main",
    "https://raw.githubusercontent.com/denuchaew877-sudo/unitates-build/main/version.json"
)
$ZipUrls = @(
    "https://codeload.github.com/denuchaew877-sudo/unitates-build/zip/refs/heads/main",
    "https://github.com/denuchaew877-sudo/unitates-build/archive/refs/heads/main.zip"
)

function Read-ConfigPair([string]$path, [string]$key) {
    if (-not (Test-Path $path)) { return "" }
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ($line -match "^\s*#" -or $line -match "^\s*$") { continue }
        if ($line -match "^\s*$([regex]::Escape($key))\s*=\s*(.+)$") {
            return $Matches[1].Trim()
        }
    }
    return ""
}

function Get-Config([string]$key, [string]$fallback = "") {
    $local = Read-ConfigPair (Join-Path $root "update-config.local.txt") $key
    if ($local) { return $local }
    $shared = Read-ConfigPair (Join-Path $root "update-config.txt") $key
    if ($shared) { return $shared }
    return $fallback
}

function Parse-VersionJson([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    $clean = $text.Trim().Trim([char]0xFEFF)
    try { return [string]($clean | ConvertFrom-Json).version } catch { return "" }
}

function Read-VersionFile([string]$path) {
    if (-not (Test-Path $path)) { return "" }
    try { return Parse-VersionJson (Get-Content $path -Raw -Encoding UTF8) } catch { return "" }
}

function Version-Number([string]$value) {
    $parts = @(($value -split "[^0-9]") | Where-Object { $_ -ne "" })
    while ($parts.Count -lt 3) { $parts += "0" }
    return ([int]$parts[0] * 1000000) + ([int]$parts[1] * 1000) + [int]$parts[2]
}

function Get-WebText([string]$url, [int]$seconds = 20) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec $seconds -Headers @{ "User-Agent" = "UnitatesUpdater" }
        return [string]$response.Content
    }
    catch {
        return ""
    }
}

function Get-RemoteVersion {
    foreach ($url in $VersionUrls) {
        $text = Get-WebText $url 15
        if (-not $text) { continue }
        if ($url -like "*api.github.com*") {
            try {
                $json = $text | ConvertFrom-Json
                if ($json.content) {
                    $bytes = [Convert]::FromBase64String(($json.content -replace "\s", ""))
                    $text = [Text.Encoding]::UTF8.GetString($bytes)
                }
            }
            catch { continue }
        }
        $version = Parse-VersionJson $text
        if ($version) {
            Write-Host "Версия с сервера прочитана."
            return $version
        }
    }
    return ""
}

function Start-Game {
    $exe = Join-Path $root "Unitates.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Host "Unitates.exe не найден в этой папке."
        Pause-IfNeeded
        exit 1
    }
    Write-Host "Запуск игры..."
    Start-Process -FilePath $exe -WorkingDirectory $root
}

function Pause-IfNeeded {
    if ($Host.Name -eq "ConsoleHost") { Write-Host ""; Read-Host "Нажми Enter" | Out-Null }
}

function Update-FromZip {
    Write-Host "Качаю архив сборки..."
    $zip = Join-Path $env:TEMP "unitates-build.zip"
    $extract = Join-Path $env:TEMP "unitates-build-extract"
    foreach ($url in $ZipUrls) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip -TimeoutSec 180 -Headers @{ "User-Agent" = "UnitatesUpdater" }
            if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
            Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
            $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
            if (-not $inner) { throw "Пустой архив" }
            Copy-Item -Path (Join-Path $inner.FullName "*") -Destination $root -Recurse -Force
            Write-Host "Архив разложен."
            return $true
        }
        catch {
            Write-Host "Не вышло ($url): $($_.Exception.Message)"
        }
    }
    return $false
}

function Invoke-Git([string[]]$gitArgs, [int]$timeoutSec = 90) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = "git"
    $info.Arguments = ($gitArgs | ForEach-Object { if ($_ -match "\s") { '"' + $_ + '"' } else { $_ } }) -join " "
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $info.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"
    $proc = [Diagnostics.Process]::Start($info)
    if (-not $proc.WaitForExit($timeoutSec * 1000)) {
        try { $proc.Kill() } catch { }
        Write-Host "git $($gitArgs[0]) завис больше ${timeoutSec}с — оборвал."
        return 1
    }
    return $proc.ExitCode
}

$remote = Get-Config "remote" $OfficialRemote
if (-not $remote) { $remote = $OfficialRemote }
$branch = Get-Config "branch" $OfficialBranch
if (-not $branch) { $branch = $OfficialBranch }
$mode = Get-Config "mode" "player"
$localVersion = Read-VersionFile (Join-Path $root "version.json")
$hasGame = Test-Path (Join-Path $root "Unitates.exe")
$hasGit = Test-Path (Join-Path $root ".git")

Write-Host "UNITATES  //  проверка обновлений"
Write-Host "Репозиторий: $remote"
if ($localVersion) { Write-Host "Локальная версия: $localVersion" }
else { Write-Host "Локальная версия: неизвестна" }

$remoteVersion = Get-RemoteVersion
if ($remoteVersion) { Write-Host "На сервере: $remoteVersion" }
else { Write-Host "На сервере: зеркала не ответили. Если игра уже есть — просто запущу." }
Write-Host ""

$remoteNewer = $remoteVersion -and ((Version-Number $remoteVersion) -gt (Version-Number $localVersion))

if ($mode -eq "dev" -and $remoteNewer) {
    Write-Host "На сервере новее. Патчу, mode=dev не держу."
    $mode = "player"
}
elseif ($mode -eq "dev") {
    Write-Host "mode=dev: локальный билд не затираю. Игроку надо удалить update-config.local.txt"
    Write-Host ""
    Start-Game
    exit 0
}

if (-not $hasGit) {
    if (-not $remoteNewer) {
        if ($hasGame) {
            Write-Host "Это ZIP-папка без Git. Версия не старше сервера — Git не нужен."
            Write-Host ""
            Start-Game
            exit 0
        }
        Write-Host "Нет ни Git, ни Unitates.exe."
        Pause-IfNeeded
        exit 1
    }
    Write-Host "Сервер новее. Обновляю архивом, без полного git fetch."
    if (Update-FromZip) {
        Write-Host "Теперь версия: $(Read-VersionFile (Join-Path $root 'version.json'))"
        Write-Host ""
        Start-Game
        exit 0
    }
    Write-Host "Архив не скачался. Запускаю то, что есть."
    Write-Host ""
    Start-Game
    exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    if ($remoteNewer) { [void](Update-FromZip) }
    Write-Host ""
    Start-Game
    exit 0
}

$origin = git remote get-url origin 2>$null
if (-not $origin) { git remote add origin $remote }
elseif ($origin -ne $remote) { git remote set-url origin $remote }

if (-not $remoteNewer -and $hasGame) {
    $localHead = git rev-parse --verify HEAD 2>$null
    $remoteHead = git rev-parse --verify "origin/$branch" 2>$null
    if ($localHead -and $remoteHead -and ($localHead -eq $remoteHead)) {
        Write-Host "Обновлений нет."
        Write-Host ""
        Start-Game
        exit 0
    }
}

Write-Host "Спрашиваю GitHub (не дольше 90с)..."
$code = Invoke-Git @("-c", "http.version=HTTP/1.1", "fetch", "--depth", "1", "--prune", "origin", $branch) 90
if ($code -ne 0) {
    Write-Host "git fetch не вышел."
    if ($remoteNewer) { [void](Update-FromZip) }
    elseif ($hasGame) { Write-Host "Игра на месте, запускаю без патча." }
    Write-Host ""
    Start-Game
    exit 0
}

$remoteHead = git rev-parse --verify "origin/$branch" 2>$null
$localHead = git rev-parse --verify HEAD 2>$null
if ($localHead -and $remoteHead -and ($localHead -eq $remoteHead) -and -not $remoteNewer) {
    Write-Host "Обновлений нет."
    Write-Host ""
    Start-Game
    exit 0
}

Write-Host "Есть патч. Ставлю файлы с origin/$branch..."
git checkout -B $branch 2>$null
$code = Invoke-Git @("reset", "--hard", "origin/$branch") 60
if ($code -ne 0 -and $remoteNewer) { [void](Update-FromZip) }

$after = Read-VersionFile (Join-Path $root "version.json")
if ($after) { Write-Host "Теперь версия: $after" }
Write-Host "Готово."
Write-Host ""
Start-Game
