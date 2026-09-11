$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

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

function Start-Game {
    $exe = Join-Path $root "Unitates.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Host "Unitates.exe не найден. Сначала скачай игру через Git."
        Pause-IfNeeded
        exit 1
    }
    Write-Host "Запуск игры..."
    Start-Process -FilePath $exe -WorkingDirectory $root
}

function Pause-IfNeeded {
    if ($Host.Name -eq "ConsoleHost") { Write-Host ""; Read-Host "Нажми Enter" | Out-Null }
}

$remote = Get-Config "remote"
$branch = Get-Config "branch" "main"
$mode = Get-Config "mode" "player"

Write-Host "UNITATES  //  проверка обновлений"
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git не установлен. Скачай https://git-scm.com/download/win"
    Write-Host "Без Git автообновление не работает — запускаю локальную копию."
    Write-Host ""
    Start-Game
    exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $root ".git"))) {
    if (-not $remote) {
        Write-Host "Это ещё не Git-копия и в update-config.txt нет remote=..."
        Write-Host "Друг должен один раз клонировать репозиторий, либо укажи URL."
        Write-Host ""
        Start-Game
        exit 0
    }
    Write-Host "Первая установка. Подключаю $remote"
    git init -b $branch | Out-Null
    git remote add origin $remote
}

$origin = git remote get-url origin 2>$null
if (-not $origin -and $remote) {
    git remote add origin $remote
}
elseif ($remote -and $origin -and $origin -ne $remote) {
    git remote set-url origin $remote
}

if ($mode -eq "dev") {
    Write-Host "Режим сборки: обновление с сервера пропущено."
    Write-Host ""
    Start-Game
    exit 0
}

Write-Host "Спрашиваю сервер..."
git fetch origin $branch 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Сеть недоступна или remote неверный. Запускаю то, что уже скачано."
    Write-Host ""
    Start-Game
    exit 0
}

$remoteHead = git rev-parse --verify "origin/$branch" 2>$null
$localHead = git rev-parse --verify HEAD 2>$null
if (-not $remoteHead) {
    Write-Host "Ветка origin/$branch не найдена. Запускаю локальную копию."
    Write-Host ""
    Start-Game
    exit 0
}

if ($localHead -eq $remoteHead) {
    $version = "локальная"
    $versionFile = Join-Path $root "version.json"
    if (Test-Path $versionFile) {
        try { $version = (Get-Content $versionFile -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { }
    }
    Write-Host "Обновлений нет. Версия актуальна."
    Write-Host ""
    Start-Game
    exit 0
}

Write-Host "Есть патч. Качаю только недостающие и изменённые файлы..."
git checkout -B $branch | Out-Null
git reset --hard "origin/$branch"
if (Get-Command git-lfs -ErrorAction SilentlyContinue) {
    git lfs pull
}
Write-Host "Готово."
Write-Host ""
Start-Game
