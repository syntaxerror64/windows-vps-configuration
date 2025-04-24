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

=== System Info ===
CPU Usage: $(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | Where-Object { $_.Name -eq "_Total" } | Select-Object -ExpandProperty PercentProcessorTime)%
Memory Usage: $([math]::Round((Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty TotalVisibleMemorySize -First 1) / 1MB - (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty FreePhysicalMemory -First 1) / 1MB, 2)) GB

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

    # Очистка старых файлов
    if (Test-Path $InstallDir) {
        Write-Host "🗑️ Удаление старых файлов в $InstallDir..."
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
    }
    Write-Host "📂 Создание директории для установки: $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction Stop | Out-Null

    # Проверка доступности URL
    Write-Host "🔍 Проверка доступности $XrayUrl..."
    try {
        $webRequest = [System.Net.WebRequest]::Create($XrayUrl)
        $webRequest.Method = "HEAD"
        $response = $webRequest.GetResponse()
        $response.Close()
    }
    catch {
        throw "Не удалось получить доступ к $XrayUrl: $_"
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
    $socksUsername = Read-Host "Введите логин (только буквы, цифры, _, -)"
    if (-not $socksUsername -or $socksUsername -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Логин должен содержать только буквы, цифры, '_' или '-' и не быть пустым"
    }
    $socksPassword = Generate-RandomPassword
    Write-Host "🔑 Сгенерирован случайный пароль: $socksPassword"

    $port = Get-Random -Minimum 20000 -Maximum 60000
    # Проверка занятости порта
    Write-Host "🔍 Проверка доступности порта $port..."
    $portInUse = Test-NetConnection -ComputerName "localhost" -Port $port -InformationLevel Quiet -ErrorAction SilentlyContinue
    if ($portInUse) {
        throw "Порт $port уже занят. Попробуйте запустить скрипт снова."
    }

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
        Write-Host "`n📄 Содержимое config.json:`n$configJson"
    }
    catch {
        Write-Host "❌ Ошибка в формате JSON конфигурации: $_" -ForegroundColor Red
        throw "JSON configuration error: $_"
    }

    Write-Host "🔍 Тестирование запуска xray.exe..."
    $timeoutSeconds = 10
    $stdoutFile = "$env:TEMP\xray_test_stdout.txt"
    $stderrFile = "$env:TEMP\xray_test_stderr.txt"
    $process = Start-Process -FilePath $XrayExe -ArgumentList "run -c `"$configPath`"" -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -NoNewWindow -PassThru
    $waitResult = $process.WaitForExit($timeoutSeconds * 1000)
    
    if (-not $waitResult) {
        $process.Kill()
        $stdout = Get-Content -Path $stdoutFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -Path $stderrFile -Raw -ErrorAction SilentlyContinue
        Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
        $errorMsg = "Тестирование xray.exe зависло после $timeoutSeconds секунд. Stdout: $stdout`nStderr: $stderr"
        Save-DebugLog -ErrorMessage $errorMsg -ConfigPath $configPath -XrayLogPath $LogFile
        throw $errorMsg
    }

    $stdout = Get-Content -Path $stdoutFile -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -Path $stderrFile -Raw -ErrorAction SilentlyContinue
    $testOutput = "$stdout`n$stderr"
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
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

    # Открытие порта в брандмауэре
    Write-Host "🔧 Открытие порта $port в брандмауэре..."
    try {
        New-NetFirewallRule -Name "XraySocks_$port" -DisplayName "Xray Socks Port $port" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "⚠️ Не удалось открыть порт $port в брандмауэре: $_" -ForegroundColor Yellow
    }

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
    Write-Host "`n⚠️ Проверьте, что антивирус не блокирует xray.exe."
}
catch {
    Save-DebugLog -ErrorMessage $_.Exception.Message -ConfigPath $configPath -XrayLogPath $LogFile
    Write-Host "❌ Критическая ошибка: $_" -ForegroundColor Red
    exit 1
}
