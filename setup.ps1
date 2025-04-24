$ErrorActionPreference = "Stop"

function Write-Status($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
}

function Ensure-Winget {
    Write-Status "`n🔍 Проверка наличия Winget..." Cyan
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Status "🚧 Winget не найден. Устанавливаем зависимости..." Yellow
        $temp = "$env:TEMP\winget-install"
        New-Item -ItemType Directory -Path $temp -Force | Out-Null

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
        @{ name = "Total Commander"; id = "Ghisler.TotalCommander" },
        @{ name = "Visual Studio Code"; id = "Microsoft.VisualStudioCode" }
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

    # Альтернативный метод установки VS Code через прямое скачивание
    Write-Status "`n⬇️ Устанавливаем Visual Studio Code (альтернативный метод)..." Cyan
    try {
        if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
            Invoke-WebRequest -Uri https://aka.ms/win32-x64-user-stable -OutFile "$env:TEMP\vscode-install.exe"
            Start-Process -FilePath "$env:TEMP\vscode-install.exe" -Args "/silent /mergetasks=!runcode" -Wait
            Remove-Item "$env:TEMP\vscode-install.exe" -Force -ErrorAction SilentlyContinue
            Write-Status "✅ Visual Studio Code установлен (альтернативный метод)." Green
        } else {
            Write-Status "✅ Visual Studio Code уже установлен." Green
        }
    } catch {
        Write-Status "❌ Ошибка установки Visual Studio Code (альтернативный метод): $_" Red
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
        $LangTag = "ru-RU"
        $LangList = New-WinUserLanguageList $LangTag
        $LangList.Add("en-US")
        Set-WinUserLanguageList $LangList -Force
        Set-WinUILanguageOverride -Language $LangTag
        Set-WinSystemLocale $LangTag
        Set-Culture $LangTag
        Set-WinHomeLocation -GeoId 203

        # Установка языкового пакета (если он ещё не установлен)
        Install-Language -Language $LangTag -Confirm:$false -Force

        Write-Status "✅ Язык системы изменён на русский. Требуется перезагрузка." Green
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

function Install-WSL {
    Write-Status "`n🐧 Устанавливаем WSL с дистрибутивом Ubuntu..." Cyan
    try {
        if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
            wsl --install -d Ubuntu
            Write-Status "✅ WSL и Ubuntu установлены. Требуется перезагрузка." Green
        } else {
            Write-Status "✅ WSL уже установлен." Green
        }
    } catch {
        Write-Status "❌ Ошибка установки WSL: $_" Red
    }
}

function Show-Menu {
    Write-Host "`n📋 Выберите режим работы скрипта:" -ForegroundColor Cyan
    Write-Host "1. 🧰 Установить и настроить всё"
    Write-Host "2. 🔧 Выполнить только одну задачу"
    Write-Host "3. ✅ Выбрать несколько задач"
    $choice = Read-Host "`nВведите номер (1-3)"

    switch ($choice) {
        '1' {
            Ensure-Winget
            Show-HiddenFiles
            Install-Apps
            Set-RussianLanguage
            Disable-UAC
            Run-Debloat
            Install-WSL
        }
        '2' {
            Show-SingleTaskMenu
        }
        '3' {
            Show-MultiTaskMenu
        }
        default {
            Write-Status "Неверный выбор. Завершение." Red
        }
    }
}

function Show-SingleTaskMenu {
    Write-Host "`n🔧 Выберите задачу:" -ForegroundColor Cyan
    Write-Host "1. Установить Winget"
    Write-Host "2. Показать скрытые файлы"
    Write-Host "3. Установить программы"
    Write-Host "4. Установить русский язык"
    Write-Host "5. Отключить UAC"
    Write-Host "6. Выполнить debloat"
    Write-Host "7. Установить WSL с Ubuntu"

    $task = Read-Host "Введите номер (1-7)"
    switch ($task) {
        '1' { Ensure-Winget }
        '2' { Show-HiddenFiles }
        '3' { Install-Apps }
        '4' { Set-RussianLanguage }
        '5' { Disable-UAC }
        '6' { Run-Debloat }
        '7' { Install-WSL }
        default { Write-Status "Неверный выбор" Red }
    }
}

function Show-MultiTaskMenu {
    Write-Host "`n✅ Укажите номера задач через запятую (например: 1,3,5):" -ForegroundColor Cyan
    Write-Host "1. Установить Winget"
    Write-Host "2. Показать скрытые файлы"
    Write-Host "3. Установить программы"
    Write-Host "4. Установить русский язык"
    Write-Host "5. Отключить UAC"
    Write-Host "6. Выполнить debloat"
    Write-Host "7. Установить WSL с Ubuntu"

    $input = Read-Host "Введите номера"
    $tasks = $input -split ',' | ForEach-Object { $_.Trim() }

    foreach ($task in $tasks) {
        switch ($task) {
            '1' { Ensure-Winget }
            '2' { Show-HiddenFiles }
            '3' { Install-Apps }
            '4' { Set-RussianLanguage }
            '5' { Disable-UAC }
            '6' { Run-Debloat }
            '7' { Install-WSL }
            default { Write-Status "Неверный номер задачи: $task" Red }
        }
    }
}

# Точка входа
Write-Status "`n🚀 Запуск скрипта установки и настройки системы..." Green
Show-Menu
Write-Status "`n🟢 Готово! Перезагрузите систему для применения всех изменений." Cyan
