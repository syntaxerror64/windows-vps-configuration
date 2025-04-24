# Установка и настройка Xray + Reality с автозапуском и автогенерацией ключей

$ErrorActionPreference = "Stop"

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
    "www.apple.com",
    "www.cloudflare.com",
    "www.github.com",
    "www.amazon.com",
    "www.facebook.com",
    "www.twitter.com"
)

Write-Host "=============================================="
Write-Host "🚀 Начало установки Xray + Reality"
Write-Host "=============================================="

# Создание директории для установки
if (-Not (Test-Path $InstallDir)) {
    Write-Host "📂 Создание директории для установки: $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

# Скачивание и распаковка Xray
Write-Host "⬇️ Скачивание Xray..."
try {
    Invoke-WebRequest -Uri $XrayUrl -OutFile $ZipPath
    Write-Host "📦 Распаковка архива..."
    Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
    Remove-Item $ZipPath
    Write-Host "✅ Xray успешно установлен"
}
catch {
    Write-Host "❌ Ошибка при скачивании или распаковке Xray: $_" -ForegroundColor Red
    exit 1
}

$XrayExe = Join-Path $InstallDir "xray.exe"

function Generate-RandomShortId {
    $chars = "0123456789abcdef"
    $shortId = ""
    for ($i = 0; $i -lt 8; $i++) {
        $shortId += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $shortId
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

Set-Content -Path (Join-Path $InstallDir "config.json") -Value $configJson -Encoding UTF8

# Создание службы Windows
Write-Host "🛠️ Создание службы Windows..."
try {
    sc.exe create $ServiceName binPath= "`"$XrayExe`" run -c `"$(Join-Path $InstallDir "config.json")`"" start= auto
    sc.exe failure $ServiceName reset= 0 actions= restart/5000/restart/5000/restart/5000
    Start-Service -Name $ServiceName
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
PrivateKey: $($keys.Private)

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
