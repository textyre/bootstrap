# ============================================
# ПРОВЕРКА ПОДКЛЮЧЕНИЯ К СЕРВЕРУ
# ============================================

# Загружаем конфигурацию
. "$PSScriptRoot\..\config\config.ps1"
. "$PSScriptRoot\modules\ssh-copy-id.ps1"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      ПРОВЕРКА ПОДКЛЮЧЕНИЯ К СЕРВЕРУ      ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "Сервер: $Global:SERVER_USER@${Global:SERVER_HOST}:$Global:SERVER_PORT" -ForegroundColor Yellow
Write-Host ""

# Проверяем наличие ключа
if (!(Test-Path $Global:SSH_KEY)) {
    Write-Host "✗ SSH ключ не найден" -ForegroundColor Red
    Write-Host "  Запустите сначала: .\ssh\setup_ssh_key.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "✓ SSH ключ найден: $Global:KEY_NAME" -ForegroundColor Green
Write-Host ""

# Тестируем подключение
$success = Test-SSHConnection `
    -KeyPath $Global:SSH_KEY `
    -ServerUser $Global:SERVER_USER `
    -ServerHost $Global:SERVER_HOST `
    -ServerPort $Global:SERVER_PORT

if ($success) {
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host "✓ Подключение работает отлично!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    # Получаем информацию о сервере
    Write-Host "Информация о сервере:" -ForegroundColor Cyan
    $uname = ssh -i $Global:SSH_KEY -p $Global:SERVER_PORT "$Global:SERVER_USER@$Global:SERVER_HOST" "uname -a" 2>&1
    Write-Host "  $uname" -ForegroundColor Gray
    Write-Host ""
    
    exit 0
} else {
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Red
    Write-Host "✗ Подключение не работает" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Возможные причины:" -ForegroundColor Yellow
    Write-Host "  • Сервер недоступен" -ForegroundColor Gray
    Write-Host "  • Неверный порт или адрес" -ForegroundColor Gray
    Write-Host "  • SSH ключ не был скопирован на сервер" -ForegroundColor Gray
    Write-Host "  • Проблемы с правами на ~/.ssh/authorized_keys" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Попробуйте:" -ForegroundColor Yellow
    Write-Host "  1. Проверить config.ps1" -ForegroundColor Gray
    Write-Host "  2. Запустить заново: .\ssh\setup_ssh_key.ps1" -ForegroundColor Gray
    Write-Host ""
    
    exit 1
}

