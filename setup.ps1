# setup.ps1

$ErrorActionPreference = "Stop"

function Write-Status($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
}

function Ensure-Winget {
    Write-Status "`n🔍 Проверка наличия Winget..." Cyan
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Status "🚧 Winget не найден. Пытаемся установить все зависимости..." Yellow
        $temp = "$env:TEMP\winget-install"
        New-Item -ItemType Directory -Path $temp -Force | Out-Null

        # Зависимости
        $vclibs = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $xamlZip = "$temp\Xaml.zip"
        $xamlUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
        $xamlExtractPath = "$temp\xaml"
        $wingetUri = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"

        Invoke-WebRequest $vclibs -OutFile "$temp\VCLibs.appx"
        Invoke-WebRequest $xamlUrl -OutFile $xamlZip
        Expand-Archive $xamlZip -DestinationPath $xamlExtractPath -Force
        Copy-Item "$xamlExtractPath\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx" "$temp\Xaml.appx"

        Invoke-WebRequest $wingetUri -OutFile "$temp\winget.msixbundle"

        Add-AppxPackage -Path "$temp\VCLibs.appx"
        Add-AppxPackage -Path "$temp\Xaml.appx"
        Add-AppxPackage -Path "$temp\winget.msixbundle"

        Start-Sleep -Seconds 5
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            Write-Status "❌ Не удалось установить Winget." Red
            exit 1
        }
        Write-Status "✅ Winget установлен." Green
    } else {
        Write-Status "✅ Winget уже установлен."
    }
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
        Write-Status "`n⬇️ Устанавливаем $($app.name)..." Cyan
        try {
            winget install --id $($app.id) --silent --accept-source-agreements --accept-package-agreements
            Write-Status "✅ $($app.name) установлен." Green
        } catch {
            Write-Status "❌ Ошибка установки $($app.name): $_" Red
        }
    }
}

function Show-HiddenFiles {
    Write-Status "`n🛠️ Включаем отображение скрытых файлов..." Cyan
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Hidden -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSuperHidden -Value 1
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Write-Status "✅ Скрытые файлы теперь видны." Green
}

function Set-RussianLanguage {
    Write-Status "`n🌍 Настройка языка системы: русский + английский..." Cyan
    try {
        $LangList = New-WinUserLanguageList ru-RU
        $LangList.Add("en-US")
        Set-WinUserLanguageList $LangList -Force
        Set-WinUILanguageOverride -Language "ru-RU"
        Set-WinSystemLocale ru-RU
        Set-Culture ru-RU
        Write-Status "✅ Язык системы изменён. Требуется перезагрузка." Green
    } catch {
        Write-Status "❌ Не удалось изменить язык: $_" Red
    }
}

function Disable-UAC {
    Write-Status "`n🔒 Отключаем UAC..." Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0
        Write-Status "✅ UAC отключён. Требуется перезагрузка." Green
    } catch {
        Write-Status "❌ Не удалось отключить UAC: $_" Red
    }
}

function Run-Debloat {
    Write-Status "`n🚀 Запуск debloat-скрипта..." Magenta
    try {
        & ([scriptblock]::Create((irm "https://debloat.raphi.re/")))
    } catch {
        Write-Status "❌ Не удалось запустить debloat: $_" Red
    }
}

# Главная точка входа
Write-Status "`n📦 Начинаем установку и настройку системы..." Cyan

try {
    Ensure-Winget
    Show-HiddenFiles
    Install-Apps
    Set-RussianLanguage
    Disable-UAC
    Run-Debloat

    Write-Status "`n🎉 Все шаги завершены! Перезагрузите ПК для применения всех изменений." Green
} catch {
    Write-Status "❌ Ошибка выполнения скрипта: $_" Red
}
