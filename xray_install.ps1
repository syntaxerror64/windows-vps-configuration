# Установка и настройка Xray + Socks с автозапуском

$ErrorActionPreference = "Stop"

# Функция для сохранения лога отладки
function Save-DebugLog {
    param (
        [string]$ErrorMessage,
        [string]$ConfigPath,
        [string]$XrayLogPath
    )
    $DebugLogPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "debug_log.txt"
    $DebugContent = @"
=== Debug Log ===
Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Error Message: $ErrorMessage

=== Contents of config.json ===
$(if (Test-Path $ConfigPath) { Get-Content -Path $ConfigPath -Raw } else { "config.json not found" })

=== Contents of xray.log ===
$(if (Test-Path $XrayLogPath) { Get-Content -Path $XrayLogPath -Raw } else { "xray.log not found" })

=== Windows Event Log for XrayRealityService ===
"@
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Service Control Manager'
            Level = 2,3
            StartTime = (Get-Date).AddHours(-1)
        } -ErrorAction SilentlyContinue | Where-Object { $_.Message -like "*XrayRealityService*" } | ForEach-Object {
            "Time: $($_.TimeCreated)`nID: $($_.Id)`nMessage: $($_.Message)`n---"
        }
        if ($events) {
            $DebugContent += $events -join "`n"
        } else {
            $DebugContent += "No relevant events found in System log for XrayRealityService"
        }
    }
    catch {
        $DebugContent += "Failed to retrieve Windows Event Log: $_"
    }
    try {
        [System.IO.File]::WriteAllText($DebugLogPath, $DebugContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host "📝 Лог отладки сохранен: $DebugLogPath" -ForegroundColor Yellow
    }
    catch {
        Write-Host "❌ Ошибка при сохранении лога отладки: $_" -ForegroundColor Red
    }
}

try {
    # Проверка прав администратора
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "❌ Скрипт должен быть запущен с правами администратора!" -ForegroundColor Red
        throw "Script not run as administrator"
    }

    # Конфигурационные параметры
    $InstallDir = "C:\Program Files\XrayReality"
    $XrayUrl = "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip"
    $ServiceName = "XrayRealityService"
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $KeysFile = Join-Path $DesktopPath "keys.txt"
    $ZipPath = "$env:TEMP\Xray.zip"
    $LogFile = Join-Path $InstallDir "xray.log"
    $configPath = Join-Path $InstallDir "config.json"

    Write-Host "=============================================="
    Write-Host "🚀 Начало установки Xray + Socks"
    Write-Host "=============================================="

    if (-Not (Test-Path $InstallDir)) {
        Write-Host "📂 Создание директории для установки: $InstallDir"
        New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction Stop | Out-Null
    }

    Write-Host "⬇️ Скачивание Xray..."
    Invoke-WebRequest -Uri $XrayUrl -OutFile $ZipPath -ErrorAction Stop
    Write-Host "📦 Распаковка архива..."
    Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force -ErrorAction Stop
    Remove-Item $ZipPath -ErrorAction Stop
    Write-Host "✅ Архив Xray успешно распакован"

    Write-Host "🔍 Поиск xray.exe в директории $InstallDir..."
    $XrayExe = Get-ChildItem -Path $InstallDir -Recurse -Include "xray.exe" -ErrorAction Stop | Select-Object -First 1 -ExpandProperty FullName
    if (-Not $XrayExe) {
        throw "Файл xray.exe не найден"
    }
    Write-Host "✅ Найден xray.exe: $XrayExe"

    function Generate-RandomPassword {
        $length = 12
        $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
        $password = -join (1..$length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
        return $password
    }

    Write-Host "`n🔐 Введите учетные данные для SOCKS-подключения"
    $socksUsername = Read-Host "Введите логин"
    $socksPassword = Generate-RandomPassword
    Write-Host "🔑 Сгенерирован случайный пароль: $socksPassword"

    $port = Get-Random -Minimum 20000 -Maximum 60000
    $uuid = [guid]::NewGuid().ToString()

    Write-Host "`n🛠️ Генерация параметров подключения:"
    Write-Host "  - Порт: $port"

    $escapedLogFile = $LogFile -replace '\\', '\\\\'

    $configJson = @"
{
  "log": {
    "loglevel": "warning",
    "access": "$escapedLogFile",
    "error": "$escapedLogFile"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$socksUsername",
            "pass": "$socksPassword"
          }
        ],
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
"@

    try {
        $configJson | ConvertFrom-Json -ErrorAction Stop | Out-Null
        [System.IO.File]::WriteAllText($configPath, $configJson, [System.Text.UTF8Encoding]::new($false))
        Write-Host "✅ Конфигурационный файл успешно создан: $configPath"
    }
    catch {
        Write-Host "❌ Ошибка в формате JSON конфигурации: $_" -ForegroundColor Red
        throw "JSON configuration error: $_"
    }

    Write-Host "🔍 Тестирование запуска xray.exe..."
    $testOutput = & $XrayExe run -c $configPath 2>&1
    Write-Host "ℹ️ Вывод xray.exe: $testOutput"
    if ($testOutput -match "error" -or $testOutput -match "failed") {
        throw "Обнаружена ошибка в выводе xray.exe: $testOutput"
    }

    Write-Host "🛠️ Создание службы Windows..."
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "🗑️ Удаление существующей службы $ServiceName..."
        if ($service.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        }
        & sc.exe delete $ServiceName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Не удалось удалить службу $ServiceName"
        }
        Start-Sleep -Seconds 2
    }

    $binPath = "`"$XrayExe`" run -c `"$configPath`""
    New-Service -Name $ServiceName `
                -BinaryPathName $binPath `
                -DisplayName "Xray Socks Service" `
                -StartupType Automatic `
                -ErrorAction Stop | Out-Null

    & sc.exe failure $ServiceName reset= 0 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось настроить параметры перезапуска службы"
    }

    Write-Host "🚀 Запуск службы $ServiceName..."
    Start-Service -Name $ServiceName -ErrorAction Stop
    Write-Host "✅ Служба успешно создана и запущена"

    $connectionInfo = @"
=== Параметры подключения ===
Сервер: $(hostname)
Порт: $port
Протокол: socks
Логин: $socksUsername
Пароль: $socksPassword

=== QR-код для клиента ===
socks://$socksUsername`:$socksPassword@$(hostname)`:$port#XraySocks

=== Команда для Linux-клиента ===
xray socks -inbound `"socks://$socksUsername`:$socksPassword@:$port`" -outbound `"outbound= freedom`"
"@

    [System.IO.File]::WriteAllText($KeysFile, $connectionInfo, [System.Text.UTF8Encoding]::new($false))
    Write-Host "✅ Параметры подключения сохранены в файл: $KeysFile"

    Write-Host "`n=============================================="
    Write-Host "✅ Установка успешно завершена!"
    Write-Host "🔑 Параметры подключения сохранены в файл:"
    Write-Host "   $KeysFile"
    Write-Host "=============================================="
    Write-Host "`nДля подключения используйте следующие параметры:"
    Write-Host "Сервер: $(hostname)"
    Write-Host "Порт: $port"
    Write-Host "Логин: $socksUsername"
    Write-Host "Пароль: $socksPassword"
    Write-Host "`nМожете отсканировать QR-код из файла keys.txt для быстрого подключения"
}
catch {
    Save-DebugLog -ErrorMessage $_.Exception.Message -ConfigPath $configPath -XrayLogPath $LogFile
    Write-Host "❌ Критическая ошибка: $_" -ForegroundColor Red
    exit 1
}
