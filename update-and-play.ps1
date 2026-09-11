$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$OfficialRemote = "https://github.com/denuchaew877-sudo/unitates-build.git"
$OfficialBranch = "main"
$VersionUrl = "https://raw.githubusercontent.com/denuchaew877-sudo/unitates-build/main/version.json"

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

function Read-VersionFile([string]$path) {
    if (-not (Test-Path $path)) { return "" }
    try { return [string](Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { return "" }
}

function Version-Number([string]$value) {
    $parts = @(($value -split "[^0-9]") | Where-Object { $_ -ne "" })
    while ($parts.Count -lt 3) { $parts += "0" }
    return ([int]$parts[0] * 1000000) + ([int]$parts[1] * 1000) + [int]$parts[2]
}

function Get-RemoteVersion {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $VersionUrl -TimeoutSec 15
        return [string]($response.Content | ConvertFrom-Json).version
    }
    catch {
        return ""
    }
}

function Write-LocalVersion {
    $version = Read-VersionFile (Join-Path $root "version.json")
    if ($version) { Write-Host "Локальная версия: $version" }
    else { Write-Host "Локальная версия: неизвестна" }
}

function Start-Game {
    $exe = Join-Path $root "Unitates.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Host "Unitates.exe не найден. Нужна папка с игрой, не ярлык."
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
    Write-Host "Git не смог обновить. Качаю архив с GitHub..."
    $zip = Join-Path $env:TEMP "unitates-build.zip"
    $extract = Join-Path $env:TEMP "unitates-build-extract"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/denuchaew877-sudo/unitates-build/archive/refs/heads/main.zip" -OutFile $zip -TimeoutSec 180
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
        if (-not $inner) { throw "Пустой архив" }
        Copy-Item -Path (Join-Path $inner.FullName "*") -Destination $root -Recurse -Force
        Write-Host "Файлы из архива скопированы."
        return $true
    }
    catch {
        Write-Host "Архив не скачался: $($_.Exception.Message)"
        return $false
    }
}

$remote = Get-Config "remote" $OfficialRemote
if (-not $remote) { $remote = $OfficialRemote }
$branch = Get-Config "branch" $OfficialBranch
if (-not $branch) { $branch = $OfficialBranch }
$mode = Get-Config "mode" "player"
$localVersion = Read-VersionFile (Join-Path $root "version.json")
$remoteVersion = Get-RemoteVersion
$remoteNewer = $remoteVersion -and ((Version-Number $remoteVersion) -gt (Version-Number $localVersion))

Write-Host "UNITATES  //  проверка обновлений"
Write-Host "Репозиторий: $remote"
Write-LocalVersion
if ($remoteVersion) { Write-Host "На сервере: $remoteVersion" }
else { Write-Host "На сервере: не прочиталось (сеть / GitHub)" }
Write-Host ""

$localCfg = Join-Path $root "update-config.local.txt"
if ($mode -eq "dev" -and $remoteNewer) {
    Write-Host "На сервере версия новее. Игнорирую mode=dev и патчу."
    $mode = "player"
}
elseif ($mode -eq "dev") {
    Write-Host "mode=dev: локальный билд не затираю."
    Write-Host "Если ты игрок, удали update-config.local.txt и запусти play.bat снова."
    Write-Host ""
    Start-Game
    exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git не установлен."
    if ($remoteNewer -or -not $localVersion) {
        if (Update-FromZip) {
            Write-Host ""
            Start-Game
            exit 0
        }
    }
    Write-Host "Поставь Git: https://git-scm.com/download/win"
    Write-Host "Пока запускаю то, что есть."
    Write-Host ""
    Start-Game
    exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $root ".git"))) {
    Write-Host "Папка без Git. Подключаю $remote"
    git init -b $branch
    if ($LASTEXITCODE -ne 0) { git init }
    git remote remove origin 2>$null
    git remote add origin $remote
}

$origin = git remote get-url origin 2>$null
if (-not $origin) {
    git remote add origin $remote
}
elseif ($origin -ne $remote) {
    Write-Host "origin был $origin — ставлю официальный адрес."
    git remote set-url origin $remote
}

Write-Host "Спрашиваю GitHub..."
$fetchOut = git fetch --prune origin $branch 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "git fetch не вышел:"
    Write-Host ($fetchOut | Out-String)
    if ($remoteNewer -or -not $localVersion) {
        if (Update-FromZip) {
            Write-Host ""
            Start-Game
            exit 0
        }
    }
    Write-Host "Запускаю то, что уже скачано."
    Write-Host ""
    Start-Game
    exit 0
}

$remoteHead = git rev-parse --verify "origin/$branch" 2>$null
$localHead = git rev-parse --verify HEAD 2>$null
if (-not $remoteHead) {
    Write-Host "Ветка origin/$branch не найдена после fetch."
    if (Update-FromZip) {
        Write-Host ""
        Start-Game
        exit 0
    }
    Start-Game
    exit 0
}

if ($localHead -and ($localHead -eq $remoteHead) -and -not $remoteNewer) {
    Write-Host "Обновлений нет. Версия актуальна."
    Write-Host ""
    Start-Game
    exit 0
}

Write-Host "Есть патч. Качаю изменённые файлы..."
git checkout -B $branch
git reset --hard "origin/$branch"
if ($LASTEXITCODE -ne 0) {
    Write-Host "git reset не вышел. Пробую архив."
    if (-not (Update-FromZip)) {
        Pause-IfNeeded
        Start-Game
        exit 1
    }
}

if (Test-Path $localCfg) {
    $stillDev = Read-ConfigPair $localCfg "mode"
    if ($stillDev -eq "dev") {
        Write-Host "update-config.local.txt с mode=dev оставлен как был."
    }
}

$after = Read-VersionFile (Join-Path $root "version.json")
if ($after) { Write-Host "Теперь версия: $after" }
Write-Host "Готово."
Write-Host ""
Start-Game
