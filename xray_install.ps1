#Requires -Version 5
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Установка и настройка Xray с SOCKS5 прокси как службы Windows.

.DESCRIPTION
    Скрипт загружает, устанавливает и настраивает Xray с SOCKS5 прокси, создает службу,
    настраивает брандмауэр и сохраняет информацию о подключении.

.NOTES
    Требуется PowerShell 5.0+ и права администратора.
    Логи сохраняются в $env:TEMP, а отладочная информация — на рабочем столе.
#>

# Глобальные настройки
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$DebugPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Параметры установки
$InstallDir = "C:\Program Files\XrayReality"
$ServiceName = "XrayRealityService"
$LogFile = Join-Path $InstallDir "xray.log"
$ConfigPath = Join-Path $InstallDir "config.json"
$XrayUrl = "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip"
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$KeysFile = Join-Path $DesktopPath "xray_connection_info.txt"

# Функция логирования отладочной информации
function Write-DebugLog {
    param (
        [Parameter(Mandatory)][string]$ErrorMessage
    )
    try {
        $DebugLogPath = Join-Path $DesktopPath "xray_debug_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $DebugInfo = @(
            "=== Debug Info ===",
            "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "Error: $ErrorMessage",
            "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)",
            "PSVersion: $($PSVersionTable.PSVersion)",
            "User: $([Environment]::UserName)",
            "Config: $(if (Test-Path $ConfigPath) { Get-Content $ConfigPath -Raw } else { 'N/A' })",
            "Service: $(Get-Service $ServiceName -ErrorAction SilentlyContinue | Format-List | Out-String)",
            "XrayExe: $(if (Test-Path $script:XrayExe) { $script:XrayExe } else { 'Not found' })",
            "XrayLog: $(if (Test-Path $LogFile) { Get-Content $LogFile -Raw } else { 'Not found' })"
        )
        [System.IO.File]::WriteAllText($DebugLogPath, ($DebugInfo -join "`n"), [System.Text.Encoding]::UTF8)
        Write-Host "Отладочный лог сохранен: $DebugLogPath" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Ошибка записи отладочного лога: $_" -ForegroundColor Red
    }
}

# Проверка предварительных условий
function Test-Prerequisites {
    if (-not (Test-NetConnection -ComputerName "github.com" -Port 443 -InformationLevel Quiet)) {
        throw "Нет подключения к интернету."
    }
    Write-Host "Проверки окружения пройдены" -ForegroundColor Cyan
}

# Очистка предыдущей установки
function Remove-PreviousInstallation {
    if (Test-Path $InstallDir) {
        Write-Host "Очистка предыдущей установки..." -ForegroundColor Yellow
        Get-Service $ServiceName -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Remove-Item -Path $InstallDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Загрузка Xray
function Get-XrayBinary {
    $ZipPath = Join-Path $env:TEMP "xray-core.zip"
    Write-Host "Скачивание Xray..." -ForegroundColor Green
    $Timer = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-WebRequest -Uri $XrayUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec 30
    $Timer.Stop()
    $time = [math]::Round($Timer.Elapsed.TotalSeconds, 2)
    Write-Host "Загрузка завершена ($time сек.)" -ForegroundColor Green
    
    Write-Host "Распаковка архива..." -ForegroundColor Green
    Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
    Remove-Item $ZipPath -ErrorAction SilentlyContinue
    
    $script:XrayExe = Get-ChildItem -Path $InstallDir -Filter "xray.exe" -Recurse -File | Select-Object -First 1 -ExpandProperty FullName
    if (-not $XrayExe) { throw "xray.exe не найден." }
}

# Получение пользовательских данных
function Get-UserInput {
    param (
        [string]$Prompt = "Введите логин (a-z, 0-9, _, -, 3-20 символов)",
        [string]$Pattern = '^[a-zA-Z0-9_-]{3,20}$'
    )
    do {
        $input = Read-Host $Prompt
        if ($input -match $Pattern) { return $input }
        Write-Host "Некорректный ввод. Используйте a-z, 0-9, _, -, длина 3-20." -ForegroundColor Red
    } while ($true)
}

# Проверка JSON (для PowerShell 5.1 и новее)
function Test-JsonContent {
    param (
        [string]$JsonString
    )
    try {
        $null = [System.Web.Script.Serialization.JavaScriptSerializer]::new().DeserializeObject($JsonString)
        return $true
    }
    catch {
        return $false
    }
}

# Генерация конфигурации
function New-XrayConfig {
    param (
        [string]$Username,
        [string]$Password,
        [int]$Port
    )
    $LogPathEscaped = $LogFile.Replace('\', '/')
    $ConfigJson = @"
{
    "log": {
        "loglevel": "warning",
        "access": "$LogPathEscaped",
        "error": "$LogPathEscaped"
    },
    "inbounds": [{
        "port": $Port,
        "protocol": "socks",
        "settings": {
            "auth": "password",
            "accounts": [{"user": "$Username", "pass": "$Password"}],
            "udp": true
        }
    }],
    "outbounds": [{"protocol": "freedom", "settings": {}}]
}
"@
    if (-not (Test-JsonContent -JsonString $ConfigJson)) {
        throw "Ошибка в JSON конфигурации."
    }
    [System.IO.File]::WriteAllText($ConfigPath, $ConfigJson, [System.Text.Encoding]::UTF8)
}

# Настройка службы
function Install-XrayService {
    Write-Host "Проверка пути к xray.exe: $script:XrayExe" -ForegroundColor Yellow
    if (-not (Test-Path $script:XrayExe)) {
        throw "Файл xray.exe не найден по пути: $script:XrayExe"
    }
    
    Write-Host "Проверка конфигурации: $ConfigPath" -ForegroundColor Yellow
    if (-not (Test-Path $ConfigPath)) {
        throw "Файл конфигурации не найден по пути: $ConfigPath"
    }
    
    $ServiceArgs = "run -c `"$ConfigPath`""
    $BinaryPath = "`"$script:XrayExe`" $ServiceArgs"
    Write-Host "Создание службы с BinaryPathName: $BinaryPath" -ForegroundColor Yellow
    
    $ServiceParams = @{
        Name           = $ServiceName
        BinaryPathName = $BinaryPath
        DisplayName    = "Xray Reality Service"
        StartupType    = "Automatic"
        Description    = "Xray SOCKS5 Proxy Service"
    }
    
    if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {
        Write-Host "Удаление существующей службы..." -ForegroundColor Yellow
        Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
        & sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }
    
    try {
        New-Service @ServiceParams | Out-Null
        sc.exe failure $ServiceName reset= 0 actions= restart/5000 | Out-Null
        Write-Host "Запуск службы..." -ForegroundColor Yellow
        Start-Service $ServiceName -ErrorAction Stop
        Write-Host "Служба успешно запущена" -ForegroundColor Green
    }
    catch {
        throw "Ошибка при создании или запуске службы: $_"
    }
}

# Настройка брандмауэра
function Set-FirewallRule {
    param (
        [int]$Port
    )
    $RuleName = "XraySocks_$Port"
    New-NetFirewallRule -Name $RuleName `
                        -DisplayName "Xray SOCKS5 ($Port)" `
                        -Direction Inbound `
                        -Protocol TCP `
                        -LocalPort $Port `
                        -Action Allow `
                        -Enabled True `
                        -Profile Any `
                        -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Правило брандмауэра добавлено" -ForegroundColor Green
}

# Основной процесс
try {
    Start-Transcript -Path (Join-Path $env:TEMP "xray_install_$(Get-Date -Format 'yyyyMMdd-HHmmss').log") -Append
    Write-Host "Запуск установки Xray + SOCKS5 Proxy" -ForegroundColor Cyan
    
    Test-Prerequisites
    Remove-PreviousInstallation
    Get-XrayBinary
    
    $SocksUsername = Get-UserInput
    $SocksPassword = -join ((33..126 | Get-Random -Count 16) | ForEach-Object { [char]$_ })
    Write-Host "Сгенерирован пароль: $SocksPassword" -ForegroundColor Cyan
    
    do {
        $Port = Get-Random -Minimum 20000 -Maximum 60000
    } while (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
    Write-Host "Выбран порт: $Port" -ForegroundColor Cyan
    
    New-XrayConfig -Username $SocksUsername -Password $SocksPassword -Port $Port
    Install-XrayService
    Set-FirewallRule -Port $Port
    
    $ConnectionInfo = @"
=== Xray SOCKS5 Подключение ===
Сервер: $env:COMPUTERNAME
Порт: $Port
Логин: $SocksUsername
Пароль: $SocksPassword
"@
    [System.IO.File]::WriteAllText($KeysFile, $ConnectionInfo, [System.Text.Encoding]::UTF8)
    
    Write-Host "Установка завершена! Настройки сохранены в: $KeysFile" -ForegroundColor Green
}
catch {
    Write-Host "Ошибка: $_" -ForegroundColor Red
    Write-DebugLog -ErrorMessage $_.Exception.Message
    exit 1
}
finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}
