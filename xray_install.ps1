# Установка и настройка Xray + Reality с автозапуском и автогенерацией ключей

$ErrorActionPreference = "Stop"

$InstallDir = "C:\Program Files\XrayReality"
$XrayUrl = "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip"
$ServiceName = "XrayRealityService"
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$KeysFile = Join-Path $DesktopPath "keys.txt"
$ZipPath = "$env:TEMP\Xray.zip"

if (-Not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

Write-Host "Скачивание Xray..."
Invoke-WebRequest -Uri $XrayUrl -OutFile $ZipPath
Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
Remove-Item $ZipPath

$XrayExe = Join-Path $InstallDir "xray.exe"

function Generate-Keys {
    $result = & $XrayExe x25519
    $publicKey = ($result | Select-String "Public key" | ForEach-Object { $_.ToString().Split(":")[1].Trim() })
    $privateKey = ($result | Select-String "Private key" | ForEach-Object { $_.ToString().Split(":")[1].Trim() })
    return @{Public=$publicKey; Private=$privateKey}
}

function Prompt-Config {
    param ([string]$ConfigName)

    Write-Host "`nВведите настройки для конфигурации $ConfigName:"
    $uuid = [guid]::NewGuid().ToString()
    $port = Read-Host "Введите порт"
    $shortId = Read-Host "Введите shortId (Reality)"
    $serverName = Read-Host "Введите serverName (SNI)"

    Write-Host "Генерация ключей для $ConfigName..."
    $keys = Generate-Keys

    return @{
        uuid = $uuid
        port = $port
        shortId = $shortId
        serverName = $serverName
        publicKey = $keys.Public
        privateKey = $keys.Private
    }
}

$config1 = Prompt-Config "1 (SOCKS + Reality)"
$config2 = Prompt-Config "2 (дополнительная конфигурация)"

$configJson = @"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${config1.port},
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
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
          "dest": "${config1.serverName}:443",
          "xver": 0,
          "serverNames": ["${config1.serverName}"],
          "privateKey": "${config1.privateKey}",
          "shortIds": ["${config1.shortId}"]
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

# === Служба Windows ===
sc.exe create $ServiceName binPath= "`"$XrayExe -config config.json`"" start= auto
sc.exe failure $ServiceName reset= 0 actions= restart/5000/restart/5000/restart/5000
Start-Service -Name $ServiceName

# === Сохраняем данные подключения ===
$connectionInfo = @"
=== Конфигурация 1 (SOCKS + Reality) ===
UUID: ${config1.uuid}
Port: ${config1.port}
ShortID: ${config1.shortId}
ServerName: ${config1.serverName}
PublicKey: ${config1.publicKey}
PrivateKey: ${config1.privateKey}

=== Конфигурация 2 ===
UUID: ${config2.uuid}
Port: ${config2.port}
ShortID: ${config2.shortId}
ServerName: ${config2.serverName}
PublicKey: ${config2.publicKey}
PrivateKey: ${config2.privateKey}
"@

Set-Content -Path $KeysFile -Value $connectionInfo -Encoding UTF8

Write-Host "`n✅ Установка завершена. Конфигурация сохранена в $KeysFile"
