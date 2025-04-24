# Установка и настройка Xray + Reality с автозапуском

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

# Проверка прав администратора
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ Скрипт должен быть запущен с правами администратора!" -ForegroundColor Red
    Save-DebugLog -ErrorMessage "Script not run as administrator" -ConfigPath $configPath -XrayLogPath $LogFile
    exit 1
}

# Конфигурационные параметры
$InstallDir = "C:\Program Files\XrayReality"
$XrayUrl = "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip"
$ServiceName = "XrayRealityService"
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$KeysFile = Join-Path $DesktopPath "keys.txt"
$ZipPath = "$env:TEMP\Xray.zip"
$LogFile = Join-Path $InstallDir "xray.log"

$popularDomains = @(
    "www.google.com",
    "www.microsoft.com",
    "www.cloudflare.com",
    "www.github.com",
    "www.amazon.com"
)

Write-Host "=============================================="
Write-Host "🚀 Начало установки Xray + Reality"
Write-Host "=============================================="

if (-Not (Test-Path $InstallDir)) {
    Write-Host "📂 Создание директории для установки: $InstallDir"
    try {
        New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "❌ Ошибка при создании директории ${InstallDir}: $_" -ForegroundColor Red
        Save-DebugLog -ErrorMessage "Failed to create directory: $_" -ConfigPath $configPath -XrayLogPath $LogFile
        exit 1
    }
}

Write-Host "⬇️ Скачивание Xray..."
try {
    Invoke-WebRequest -Uri $XrayUrl -OutFile $ZipPath -ErrorAction Stop
    Write-Host "📦 Распаковка архива..."
    Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force -ErrorAction Stop
    Remove-Item $ZipPath -ErrorAction Stop
    Write-Host "✅ Архив Xray успешно распакован"
}
catch {
    Write-Host "❌ Ошибка при скачивании или распаковке Xray: $_" -ForegroundColor Red
    Save-DebugLog -ErrorMessage "Failed to download or extract Xray: $_" -ConfigPath $configPath -XrayLogPath $LogFile
    exit 1
}

Write-Host "🔍 Поиск xray.exe в директории $InstallDir..."
try {
    $XrayExe = Get-ChildItem -Path $InstallDir -Recurse -Include "xray.exe" -ErrorAction Stop | Select-Object -First 1 -ExpandProperty FullName
    if (-Not $XrayExe) {
        throw "Файл xray.exe не найден"
    }
    Write-Host "✅ Найден xray.exe: $XrayExe"
}
catch {
    Write-Host "❌ Ошибка при поиске xray.exe: $_" -ForegroundColor Red
    Save-DebugLog -ErrorMessage "Failed to find xray.exe: $_" -ConfigPath $configPath -XrayLogPath $LogFile
    exit 1
}

function Generate-RandomPassword {
    $length = 12
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
    $password = -join (1..$length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
    return $password
}

function Generate-RandomShortId {
    $bytes = New-Object Byte[] 4
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [System.BitConverter]::ToString($bytes).Replace("-", "").Substring(0, 8).ToLower()
}

function Generate-Keys {
    Write-Host "🔑 Генерация ключей..."
    try {
        $result = & $XrayExe x25519
        $publicKey = ($result | Select-String "Public key" | ForEach-Object { $_.ToString().Split(":")[1].Trim() })
        $privateKey = ($result | Select-String "Private key" | ForEach-Object { $_.ToString().Split(":")[1].Trim() })
        if (-not $publicKey -or -not $privateKey) {
            throw "Не удалось сгенерировать ключи"
        }
        return @{Public=$publicKey; Private=$privateKey}
    }
    catch {
        Write-Host "❌ Ошибка при генерации ключей: $_" -ForegroundColor Red
        Save-DebugLog -ErrorMessage "Failed to generate keys: $_" -ConfigPath $configPath -XrayLogPath $LogFile
        exit 1
    }
}

Write-Host "`n🔐 Введите учетные данные для SOCKS-подключения"
$socksUsername = Read-Host "Введите логин"
$socksPassword = Generate-RandomPassword
Write-Host "🔑 Сгенерирован случайный пароль: $socksPassword"

$serverName = $popularDomains | Get-Random
$shortId = Generate-RandomShortId
$port = Get-Random -Minimum 20000 -Maximum 60000
$uuid = [guid]::NewGuid().ToString()

Write-Host "`n🛠️ Генерация параметров подключения:"
Write-Host "  - Порт: $port"
Write-Host "  - ServerName: $serverName"
Write-Host "  - ShortID: $shortId"

$keys = Generate-Keys

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
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$serverName:443",
          "xver": 0,
          "serverNames": ["$serverName"],
          "privateKey": "$($keys.Private)",
          "publicKey": "$($keys.Public)",
          "shortIds": ["$shortId"],
          "maxTimeDiff": 0,
          "strict": true
        }
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

$configPath = Join-Path $InstallDir "config.json"
try {
    $configJson | ConvertFrom-Json -ErrorAction Stop | Out-Null
    [System.IO.File]::WriteAllText($configPath, $configJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "✅ Конфигурационный файл успешно создан: $configPath"
}
catch {
    Write-Host "❌ Ошибка в формате JSON конфигурации: $_" -ForegroundColor Red
    Save-DebugLog -ErrorMessage "JSON configuration error: $_" -ConfigPath $configPath -XrayLogPath $LogFile
    exit 1
}

Write-Host "🔍 Тестирование запуска xray.exe..."
try {
    $testOutput = & $XrayExe run -c $configPath 2>&1
    Write-Host "ℹ️ Вывод xray.exe: $testOutput"
    if ($testOutput -match "error" -or $testOutput -match "failed") {
        throw "Обнаружена ошибка в выводе xray.exe: $testOutput"
    }
}
catch {
    Write-Host "❌ Ошибка при тестовом запуске xray.exe: $_" -ForegroundColor Red
    Save-DebugLog -ErrorMessage "Xray test run failed: $_" -ConfigPath $configPath -XrayLogPath $LogFile
    exit 1
}

Write-Host "🛠️ Создание службы Windows..."
try {
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
                -DisplayName "Xray Reality Service" `
                -StartupType Automatic `
                -ErrorAction Stop | Out-Null

    & sc.exe failure $ServiceName reset= 0 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось настроить параметры перезапуска службы"
    }

    Write-Host "🚀 Запуск службы $ServiceName..."
    Start-Service -Name $ServiceName -ErrorAction Stop
    Write-Host "✅ Служба успешно создана и запущена"
}
catch {
    Write-Host "❌ Ошибка при создании или запуске службы: $_" -ForegroundColor Red
    Write-Host "ℹ️ Проверьте журнал событий Windows (eventvwr) и лог-файл $LogFile для дополнительной информации."
    Save-DebugLog -ErrorMessage "Service creation or start failed: $_" -ConfigPath $configPath -XrayLogPath $LogFile
    exit 1
}

$connectionInfo = @"
=== Параметры подключения ===
Сервер: $(hostname)
Порт: $port
Протокол: socks
Логин: $socksUsername
Пароль: $socksPassword
ShortID: $shortId
ServerName: $serverName
PublicKey: $($keys.Public)

=== QR-код для клиента ===
socks://$socksUsername`:$socksPassword@$(hostname)`:$port#XrayReality

=== Команда для Linux-клиента ===
xray socks -inbound `"socks://$socksUsername`:$socksPassword@:$port`" -outbound `"outbound= freedom`"
"@

try {
    [System.IO.File]::WriteAllText($KeysFile, $connectionInfo, [System.Text.UTF8Encoding]::new($false))
    Write-Host "✅ Параметры подключения сохранены в файл: $KeysFile"
}
catch {
    Write-Host "❌ Ошибка при сохранении параметров подключения: $_" -ForegroundColor Red
    Save-DebugLog -ErrorMessage "Failed to save connection info: $_" -ConfigPath $configPath -XrayLogPath $LogFile
    exit 1
}

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
