# ============================================
# НАСТРОЙКА SSH КЛЮЧА ДЛЯ АВТОМАТИЧЕСКОГО ПОДКЛЮЧЕНИЯ
# ============================================
# Модульный скрипт: использует компоненты из modules/

# Загружаем общую конфигурацию
. "$PSScriptRoot\..\config\config.ps1"

# Загружаем модули
. "$PSScriptRoot\modules\ssh-keygen.ps1"
. "$PSScriptRoot\modules\ssh-copy-id.ps1"
. "$PSScriptRoot\modules\ssh-config.ps1"

# ============================================
# ГЛАВНЫЙ ПРОЦЕСС
# ============================================

Write-Host ""
Write-Host "╔═══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   НАСТРОЙКА SSH КЛЮЧА ДЛЯ ARCH LINUX     ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Показываем текущие настройки
Show-Config

# Проверяем конфигурацию
if (!(Test-Config)) {
    Write-Host ""
    Write-Host "✗ Ошибка в конфигурации. Проверьте файл config.ps1" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Процесс состоит из 3 шагов:" -ForegroundColor Yellow
Write-Host "  1. Генерация SSH ключа (локально)" -ForegroundColor Gray
Write-Host "  2. Копирование ключа на сервер (требуется пароль)" -ForegroundColor Gray
Write-Host "  3. Обновление SSH конфигурации (локально)" -ForegroundColor Gray
Write-Host ""

$response = Read-Host "Продолжить? (Y/n)"
if ($response -eq "n" -or $response -eq "N") {
    Write-Host "Отменено пользователем" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ШАГ 1/3: Генерация SSH ключа" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$keyCreated = New-SSHKey -KeyPath $Global:SSH_KEY -Comment "${Global:SERVER_USER}@${Global:SERVER_HOST}"

if (!$keyCreated) {
    Write-Host ""
    Write-Host "✗ Не удалось создать SSH ключ" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ШАГ 2/3: Копирование ключа на сервер" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$keyCopied = Copy-SSHKey `
    -PublicKeyPath $Global:SSH_PUB_KEY `
    -ServerUser $Global:SERVER_USER `
    -ServerHost $Global:SERVER_HOST `
    -ServerPort $Global:SERVER_PORT

if (!$keyCopied) {
    Write-Host ""
    Write-Host "✗ Не удалось скопировать ключ на сервер" -ForegroundColor Red
    Write-Host "  Вы можете попробовать позже запустить только этот шаг" -ForegroundColor Yellow
    exit 1
}

# Проверяем подключение
$connectionOk = Test-SSHConnection `
    -KeyPath $Global:SSH_KEY `
    -ServerUser $Global:SERVER_USER `
    -ServerHost $Global:SERVER_HOST `
    -ServerPort $Global:SERVER_PORT

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ШАГ 3/3: Обновление SSH конфигурации" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$hostAlias = "arch-${Global:SERVER_HOST}-${Global:SERVER_PORT}"

$configUpdated = Update-SSHConfig `
    -ConfigPath $Global:SSH_CONFIG `
    -HostAlias $hostAlias `
    -ServerHost $Global:SERVER_HOST `
    -ServerPort $Global:SERVER_PORT `
    -ServerUser $Global:SERVER_USER `
    -KeyPath $Global:SSH_KEY

Write-Host ""
Write-Host "╔═══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          ✓ НАСТРОЙКА ЗАВЕРШЕНА!          ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if ($connectionOk) {
    Write-Host "✓ Подключение без пароля настроено успешно!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Теперь можете:" -ForegroundColor Yellow
    Write-Host "  • Подключаться: ssh $hostAlias" -ForegroundColor Cyan
    Write-Host "  • Синхронизировать: .\sync\sync_to_server.ps1" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "⚠ Настройка завершена, но подключение может требовать доработки" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Попробуйте подключиться вручную:" -ForegroundColor Yellow
    Write-Host "  ssh $hostAlias" -ForegroundColor Gray
    Write-Host ""
}

# Показываем список настроенных хостов
Show-SSHHosts -ConfigPath $Global:SSH_CONFIG
