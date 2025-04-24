<#
.SYNOPSIS
Установка Xray с SOCKS5 прокси и автоматической настройкой службы
#>

#region Initial Setup
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$DebugPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Запуск транскрипции для полного лога
$TranscriptPath = Join-Path $env:TEMP "xray_install_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $TranscriptPath -Append -ErrorAction Continue
#endregion

#region Debug Functions
function Save-DebugLog {
    param(
        [string]$ErrorMessage,
        [string]$ConfigPath,
        [string]$XrayLogPath
    )
    
    try {
        $DebugLogPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "xray_debug_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        
        $DebugInfo = @(
            "=== Debug Log ===",
            "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "Error: $ErrorMessage`n",
            "=== Environment ===",
            "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)",
            "PSVersion: $($PSVersionTable.PSVersion)",
            "Architecture: $([Environment]::Is64BitProcess ? 'x64' : 'x86')",
            "User: $([Environment]::UserName)",
            "Admin: $([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)`n",
            "=== Process Info ===",
            (Get-Process -Id $PID | Format-List * | Out-String),
            "=== Network Check ===",
            (Test-NetConnection -ComputerName github.com -Port 443 -InformationLevel Detailed | Out-String)
        )

        if (Test-Path $ConfigPath) {
            $DebugInfo += @(
                "`n=== Config.json ===",
                (Get-Content $ConfigPath -Raw),
                "JSON Validation: $((Test-Json (Get-Content $ConfigPath -Raw) -ErrorAction SilentlyContinue) ? 'Valid' : 'Invalid')"
            )
        }

        if (Test-Path $XrayLogPath) {
            $DebugInfo += @(
                "`n=== Xray Log ===",
                (Get-Content $XrayLogPath -Raw)
            )
        }

        $DebugInfo += @(
            "`n=== Firewall Rules ===",
            (Get-NetFirewallRule -Name "XraySocks_*" -ErrorAction SilentlyContinue | Format-Table -AutoSize | Out-String),
            "`n=== Services ===",
            (Get-Service "*Xray*" -ErrorAction SilentlyContinue | Format-Table -AutoSize | Out-String)
        )

        [System.IO.File]::WriteAllText($DebugLogPath, ($DebugInfo -join "`n"), [System.Text.Encoding]::UTF8)
        Write-Host "Debug log saved: $DebugLogPath" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Debug log error: $_" -ForegroundColor Red
    }
}
#endregion

try {
    #region Pre-Checks
    # Проверка версии PowerShell
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "Требуется PowerShell 5 или новее. Текущая версия: $($PSVersionTable.PSVersion)"
    }

    # Проверка прав администратора
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Запустите скрипт с правами администратора!"
    }

    # Проверка подключения к интернету
    if (-not (Test-NetConnection -ComputerName github.com -Port 443 -InformationLevel Quiet)) {
        throw "Нет подключения к интернету!"
    }
    #endregion

    #region Configuration
    $InstallDir = "C:\Program Files\XrayReality"
    $XrayUrl = "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip"
    $ServiceName = "XrayRealityService"
    $DesktopPath = [Environment]::GetFolderPath('Desktop')
    $KeysFile = Join-Path $DesktopPath "xray_connection_info.txt"
    $LogFile = Join-Path $InstallDir "xray.log"
    $ConfigPath = Join-Path $InstallDir "config.json"
    #endregion

    Write-Host @"
==============================================
🚀 Xray + SOCKS5 Proxy Installer
✅ Проверки окружения пройдены
==============================================
"@ -ForegroundColor Cyan

    #region Cleanup
    if (Test-Path $InstallDir) {
        Write-Host "Очистка предыдущей установки..." -ForegroundColor Yellow
        try {
            Get-Service $ServiceName -ErrorAction Stop | Stop-Service -Force
            Start-Sleep 2
        }
        catch { }
        
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    #endregion

    #region Xray Download
    Write-Host "Скачивание Xray..." -ForegroundColor Green
    $ZipPath = "$env:TEMP\xray-core.zip"
    
    try {
        $ProgressPreference = 'SilentlyContinue'
        $DownloadTimer = [System.Diagnostics.Stopwatch]::StartNew()
        
        Invoke-WebRequest -Uri $XrayUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        
        if (-not (Test-Path $ZipPath) -or (Get-Item $ZipPath).Length -eq 0) {
            throw "Файл не был загружен"
        }
    }
    catch {
        throw "Ошибка загрузки: $_"
    }
    finally {
        $ProgressPreference = 'Continue'
        $DownloadTimer.Stop()
    }

    Write-Host "✅ Загрузка завершена ($([math]::Round($DownloadTimer.Elapsed.TotalSeconds,2)) сек.)" -ForegroundColor Green
    #endregion

    #region Xray Setup
    Write-Host "Распаковка архива..." -ForegroundColor Green
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
        Remove-Item $ZipPath -ErrorAction SilentlyContinue
        
        $XrayExe = Get-ChildItem -Path $InstallDir -Recurse -Filter 'xray.exe' -File |
                   Select-Object -First 1 -ExpandProperty FullName
        
        if (-not $XrayExe) {
            throw "xray.exe не найден!"
        }
    }
    catch {
        throw "Ошибка распаковки: $_"
    }
    #endregion

    #region User Input
    function Get-ValidInput {
        param(
            [string]$Prompt,
            [string]$Pattern,
            [string]$ErrorMessage
        )
        
        do {
            $input = Read-Host $Prompt
            if ($input -match $Pattern) { return $input }
            Write-Host $ErrorMessage -ForegroundColor Red
        } while ($true)
    }

    $socksUsername = Get-ValidInput -Prompt "Введите логин (a-z, 0-9, _, -)" `
                                    -Pattern '^[a-zA-Z0-9_-]{3,20}$' `
                                    -ErrorMessage "Некорректный логин!"

    $socksPassword = -join ((33..126 | Get-Random -Count 16) | ForEach-Object { [char]$_ })
    Write-Host "🔑 Сгенерирован пароль: $socksPassword" -ForegroundColor Cyan
    #endregion

    #region Port Selection
    do {
        $port = Get-Random -Minimum 20000 -Maximum 60000
        $portInUse = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    } while ($portInUse)

    Write-Host "Выбран порт: $port" -ForegroundColor Cyan
    #endregion

    #region Config Generation
    $logPathEscaped = $LogFile.Replace('\', '/')
    
    $configJson = @"
{
  "log": {
    "loglevel": "warning",
    "access": "$logPathEscaped",
    "error": "$logPathEscaped"
  },
  "inbounds": [{
    "port": $port,
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [{
        "user": "$($socksUsername -replace '"', '\"')",
        "pass": "$($socksPassword -replace '"', '\"')"
      }],
      "udp": true
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
"@

    if (-not (Test-Json $configJson)) {
        throw "Некорректная JSON конфигурация!"
    }
    
    [System.IO.File]::WriteAllText($ConfigPath, $configJson, [System.Text.Encoding]::UTF8)
    #endregion

    #region Service Setup
    $serviceArgs = @(
        "run",
        "-c", "`"$ConfigPath`"",
        "-service"
    )

    $serviceParams = @{
        Name           = $ServiceName
        BinaryPathName = "`"$XrayExe`" $($serviceArgs -join ' ')"
        DisplayName    = "Xray Reality Service"
        StartupType    = "Automatic"
        Description    = "Xray Core Proxy Service"
    }

    try {
        $existingService = Get-Service $ServiceName -ErrorAction SilentlyContinue
        if ($existingService) {
            Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep 2
            & sc.exe delete $ServiceName | Out-Null
        }

        New-Service @serviceParams -ErrorAction Stop | Out-Null
        sc.exe failure $ServiceName reset= 0 actions= restart/5000 | Out-Null

        Start-Service $ServiceName -ErrorAction Stop
        Write-Host "✅ Служба успешно запущена" -ForegroundColor Green
    }
    catch {
        throw "Ошибка настройки службы: $_"
    }
    #endregion

    #region Firewall Rule
    try {
        $null = New-NetFirewallRule `
            -Name "XraySocks_$port" `
            -DisplayName "Xray SOCKS5 ($port)" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $port `
            -Action Allow `
            -Enabled True `
            -Profile Any `
            -ErrorAction Stop
        
        Write-Host "✅ Правило брандмауэра добавлено" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️ Ошибка брандмауэра: $_" -ForegroundColor Yellow
    }
    #endregion

    #region Final Output
    $connectionInfo = @"
=== Xray SOCKS5 Configuration ===
Server: $env:COMPUTERNAME
Port: $port
Username: $socksUsername
Password: $socksPassword

Security Tips:
1. Не передавайте пароль открытым текстом
2. Используйте TLS поверх SOCKS при необходимости
3. Регулярно обновляйте пароли

QR Code (для клиентов):
socks://$socksUsername`:$socksPassword@$env:COMPUTERNAME`:$port
"@

    [System.IO.File]::WriteAllText($KeysFile, $connectionInfo, [System.Text.Encoding]::UTF8)
    Write-Host @"

==============================================
✅ Установка завершена!
• Файл с настройками: $KeysFile
• Логи службы: $LogFile
• Управление службой: 
  - Запуск: Start-Service $ServiceName
  - Остановка: Stop-Service $ServiceName
==============================================
"@ -ForegroundColor Green
    #endregion
}
catch {
    Write-Host "`n❌ КРИТИЧЕСКАЯ ОШИБКА: $_" -ForegroundColor Red
    Save-DebugLog -ErrorMessage $_ -ConfigPath $ConfigPath -XrayLogPath $LogFile
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
