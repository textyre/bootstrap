# ============================================
# ПРОСМОТР ТЕКУЩЕЙ КОНФИГУРАЦИИ
# ============================================

# Загружаем конфигурацию
. "$PSScriptRoot\config.ps1"

Write-Host ""
Show-Config

Write-Host "Файлы проекта:" -ForegroundColor Yellow
Write-Host "  Проект:      $Global:SYNC_SOURCE_DIR" -ForegroundColor Gray
Write-Host "  Windows:     $Global:WINDOWS_DIR" -ForegroundColor Gray
Write-Host "  Документы:   $Global:DOCS_DIR" -ForegroundColor Gray
Write-Host ""

# Проверяем валидность
Write-Host "Проверка конфигурации:" -ForegroundColor Yellow
if (Test-Config) {
    Write-Host "  ✓ Конфигурация корректна" -ForegroundColor Green
} else {
    Write-Host "  ✗ Есть ошибки в конфигурации" -ForegroundColor Red
}
Write-Host ""

# Проверяем SSH ключ
Write-Host "Статус SSH ключа:" -ForegroundColor Yellow
if (Test-Path $Global:SSH_KEY) {
    Write-Host "  ✓ SSH ключ существует" -ForegroundColor Green
    $fingerprint = ssh-keygen -lf $Global:SSH_KEY 2>&1
    Write-Host "    $fingerprint" -ForegroundColor Gray
    
    # Проверяем подключение
    Write-Host ""
    Write-Host "  Тестирую подключение..." -ForegroundColor Gray
    $testResult = ssh -i $Global:SSH_KEY -p $Global:SERVER_PORT -o "BatchMode=yes" -o "ConnectTimeout=5" "$Global:SERVER_USER@$Global:SERVER_HOST" "echo 'OK'" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Подключение работает" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Не удалось подключиться" -ForegroundColor Red
        Write-Host "    $testResult" -ForegroundColor Gray
    }
} else {
    Write-Host "  ✗ SSH ключ не найден" -ForegroundColor Red
    Write-Host "    Запустите: .\ssh\setup_ssh_key.ps1" -ForegroundColor Yellow
}
Write-Host ""

# Показываем SSH config
if (Test-Path $Global:SSH_CONFIG) {
    Write-Host "SSH Config хосты:" -ForegroundColor Yellow
    . "$PSScriptRoot\..\ssh\modules\ssh-config.ps1"
    Show-SSHHosts -ConfigPath $Global:SSH_CONFIG
}

