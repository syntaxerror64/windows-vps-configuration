# Установка и настройка Xray + Reality с автозапуском

$ErrorActionPreference = "Stop"

# Проверка прав администратора
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ Скрипт должен быть запущен с правами администратора!" -ForegroundColor Red
    exit 1
}

# Конфигурационные параметры
$InstallDir = "C:\Program Files\XrayReality"
$XrayUrl = "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip"
$ServiceName = "XrayRealityService"
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$KeysFile = Join-Path $DesktopPath "keys.txt"
$ZipPath = "$env:TEMP\Xray.zip"

# Список популярных доменов для Reality
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

# Создание директории для установки
if (-Not (Test-Path $InstallDir)) {
    Write-Host "📂 Создание директории для установки: $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Скачивание и распаковка Xray
Write-Host "⬇️ Скачивание Xray..."
try {
    Invoke-WebRequest -Uri $XrayUrl -OutFile $ZipPath
    Write-Host "📦 Распаковка архива..."
    Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
    Remove-Item $ZipPath
    Write-Host "✅ Архив Xray успешно распакован"
}
catch {
    Write-Host "❌ Ошибка при скачивании или распаковке Xray: $_" -ForegroundColor Red
    exit 1
}

# Поиск xray.exe во вложенных директориях
Write-Host "🔍 Поиск xray.exe в директории $InstallDir..."
$XrayExe = Get-ChildItem -Path $InstallDir -Recurse -Include "xray.exe" | Select-Object -First 1 -ExpandProperty FullName
if (-Not $XrayExe) {
    Write-Host "❌ Файл xray.exe не найден в $InstallDir или ее поддиректориях" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Найден xray.exe: $XrayExe"

function Generate-RandomShortId {
    $bytes = New-Object Byte[] 4
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [System.BitConverter]::ToString($bytes).Replace("-", "").Substring(0, 8).ToLower()
}

function Generate-Keys {
    Write-Host "🔑 Генерация ключей..."
    $result = & $XrayExe x25519
    $publicKey = ($result | Select-String "Public key" | ForEach-Object { $_.ToString().Split(":")[1].Trim() })
    $privateKey = ($result | Select-String "Private key" | ForEach-Object { $_.ToString().Split(":")[1].Trim() })
    return @{Public=$publicKey; Private=$privateKey}
}

# Запрос только логина и пароля для SOCKS
Write-Host "`n🔐 Введите учетные данные для SOCKS-подключения"
$socksUsername = Read-Host "Введите логин"
$socksPassword = Read-Host "Введите пароль" -AsSecureString
$socksPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($socksPassword))

# Автоматическая генерация параметров
$serverName = $popularDomains | Get-Random
$shortId = Generate-RandomShortId
$port = Get-Random -Minimum 20000 -Maximum 60000
$uuid = [guid]::NewGuid().ToString()

Write-Host "`n🛠️ Генерация параметров подключения:"
Write-Host "  - Порт: $port"
Write-Host "  - ServerName: $serverName"
Write-Host "  - ShortID: $shortId"

# Генерация ключей
$keys = Generate-Keys

$configJson = @"
{
  "log": {
    "loglevel": "warning"
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
          "dest": "$serverName`:443",
          "xver": 0,
          "serverNames": ["$serverName"],
          "privateKey": "$($keys.Private)",
          "shortIds": ["$shortId"]
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
Set-Content -Path $configPath -Value $configJson -Encoding UTF8

# Создание службы Windows
Write-Host "🛠️ Создание службы Windows..."
try {
    # Проверка и удаление существующей службы
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Host "🗑️ Удаление существующей службы $ServiceName..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        & sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }

    # Создание службы
    $binPath = "`"$XrayExe`" run -c `"$configPath`""
    New-Service -Name $ServiceName `
                -BinaryPathName $binPath `
                -DisplayName "Xray Reality Service" `
                -StartupType Automatic `
                -ErrorAction Stop | Out-Null

    # Настройка автоматического перезапуска при сбоях
    & sc.exe failure $ServiceName reset= 0 actions= restart/5000/restart/5000/restart/5000 | Out-Null

    Start-Service -Name $ServiceName -ErrorAction Stop
    Write-Host "✅ Служба успешно создана и запущена"
}
catch {
    Write-Host "❌ Ошибка при создании службы: $_" -ForegroundColor Red
    exit 1
}

# Сохранение данных подключения
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

Set-Content -Path $KeysFile -Value $connectionInfo -Encoding UTF8

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
