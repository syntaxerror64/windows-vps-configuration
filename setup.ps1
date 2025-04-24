# setup.ps1
Write-Host "🔧 Начинаем установку необходимых программ..." -ForegroundColor Cyan

# Включение отображения скрытых файлов
Write-Host "🛠️ Включаем отображение скрытых файлов и папок..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Hidden -Value 1
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSuperHidden -Value 1
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
Write-Host "✅ Скрытые файлы теперь видны."

# Проверка наличия winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Winget не найден. Убедитесь, что у вас установлена последняя версия Windows." -ForegroundColor Red
    exit 1
}

# Установки через winget
$apps = @(
    @{ name = "Brave Browser"; id = "Brave.Brave" },
    @{ name = "Docker Desktop"; id = "Docker.DockerDesktop" },
    @{ name = "Python"; id = "Python.Python.3" },
    @{ name = "Notepad++"; id = "Notepad++.Notepad++" },
    @{ name = "Total Commander"; id = "Ghisler.TotalCommander" }
)

foreach ($app in $apps) {
    Write-Host "`n⬇️ Устанавливаем $($app.name)..."
    winget install --id $($app.id) --silent --accept-source-agreements --accept-package-agreements
}

Write-Host "`n✅ Установка завершена!" -ForegroundColor Green
