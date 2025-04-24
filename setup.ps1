# setup.ps1

function Ensure-Winget {
    Write-Host "`n🔍 Проверка наличия Winget..." -ForegroundColor Cyan
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Host "🚧 Winget не найден. Пытаемся установить..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
        Add-AppxPackage -Path "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
        Start-Sleep -Seconds 5
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            Write-Host "❌ Не удалось установить Winget. Завершаем скрипт." -ForegroundColor Red
            exit 1
        }
        Write-Host "✅ Winget успешно установлен." -ForegroundColor Green
    } else {
        Write-Host "✅ Winget уже установлен."
    }
}

function Show-HiddenFiles {
    Write-Host "`n🛠️ Включаем отображение скрытых файлов и папок..." -ForegroundColor Cyan
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Hidden -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSuperHidden -Value 1
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Write-Host "✅ Скрытые файлы теперь видны."
}

function Install-Apps {
    $apps = @(
        @{ name = "Brave Browser"; id = "Brave.Brave" },
        @{ name = "Docker Desktop"; id = "Docker.DockerDesktop" },
        @{ name = "Python"; id = "Python.Python.3" },
        @{ name = "Notepad++"; id = "Notepad++.Notepad++" },
        @{ name = "Total Commander"; id = "Ghisler.TotalCommander" }
    )

    foreach ($app in $apps) {
        Write-Host "`n⬇️ Устанавливаем $($app.name)..." -ForegroundColor Cyan
        try {
            winget install --id $($app.id) --silent --accept-source-agreements --accept-package-agreements
            Write-Host "✅ $($app.name) установлен." -ForegroundColor Green
        } catch {
            Write-Host "❌ Ошибка установки $($app.name): $_" -ForegroundColor Red
        }
    }
}

function Run-Debloat {
    Write-Host "`n🚀 Запуск скрипта очистки: debloat.raphi.re..." -ForegroundColor Magenta
    try {
        & ([scriptblock]::Create((irm "https://debloat.raphi.re/")))
    } catch {
        Write-Host "❌ Не удалось выполнить скрипт debloat.raphi.re: $_" -ForegroundColor Red
    }
}

function Set-RussianLanguage {
    Write-Host "`n🌍 Установка языка системы: русский и английский..." -ForegroundColor Cyan
    try {
        $LangList = New-WinUserLanguageList ru-RU
        $LangList.Add("en-US")
        Set-WinUserLanguageList $LangList -Force
        Set-WinUILanguageOverride -Language "ru-RU"
        Set-WinSystemLocale ru-RU
        Set-Culture ru-RU
        Write-Host "✅ Язык системы изменён. Требуется перезагрузка для полного применения." -ForegroundColor Green
    } catch {
        Write-Host "❌ Не удалось изменить языковые параметры: $_" -ForegroundColor Red
    }
}

function Disable-UAC {
    Write-Host "`n🔒 Отключение контроля UAC..." -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0
        Write-Host "✅ UAC отключён. Требуется перезагрузка для применения." -ForegroundColor Green
    } catch {
        Write-Host "❌ Не удалось отключить UAC: $_" -ForegroundColor Red
    }
}

# Выполнение всех шагов
Write-Host "📦 Старт установки и настройки окружения..." -ForegroundColor Cyan

Ensure-Winget
Show-HiddenFiles
Install-Apps
Set-RussianLanguage
Disable-UAC
Run-Debloat

Write-Host "`n🎉 Все шаги завершены! Перезагрузите систему для применения всех изменений." -ForegroundColor Green
