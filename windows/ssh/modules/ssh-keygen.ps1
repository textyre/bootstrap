# ============================================
# МОДУЛЬ: Генерация SSH ключа
# ============================================
# Создает уникальный SSH ключ для сервера

function New-SSHKey {
    param(
        [string]$KeyPath,
        [string]$Comment
    )
    
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Генерация SSH ключа" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Создаем директорию .ssh если не существует
    $sshDir = Split-Path -Parent $KeyPath
    if (!(Test-Path $sshDir)) {
        Write-Host "Создаю директорию .ssh..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $sshDir | Out-Null
        Write-Host "✓ Директория создана: $sshDir" -ForegroundColor Green
        Write-Host ""
    }
    
    # Проверяем, существует ли уже ключ
    if (Test-Path $KeyPath) {
        Write-Host "ℹ SSH ключ уже существует" -ForegroundColor Yellow
        Write-Host "  Путь: $KeyPath" -ForegroundColor Gray
        Write-Host ""
        
        $response = Read-Host "Пересоздать ключ? (y/N)"
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Host "✓ Используется существующий ключ" -ForegroundColor Green
            return $true
        }
        
        Write-Host ""
        Write-Host "Удаляю старый ключ..." -ForegroundColor Cyan
        Remove-Item $KeyPath -Force
        Remove-Item "${KeyPath}.pub" -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "Генерирую новый SSH ключ (Ed25519)..." -ForegroundColor Cyan
    Write-Host "  Алгоритм: Ed25519 (современный, безопасный)" -ForegroundColor Gray
    Write-Host "  Пароль: без пароля (для автоматизации)" -ForegroundColor Gray
    Write-Host ""
    
    # Генерируем ключ
    $result = ssh-keygen -t ed25519 -f $KeyPath -N '""' -C $Comment 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Ошибка при генерации ключа" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
        return $false
    }
    
    Write-Host "✓ SSH ключ создан успешно!" -ForegroundColor Green
    Write-Host "  Приватный: $KeyPath" -ForegroundColor Gray
    Write-Host "  Публичный: ${KeyPath}.pub" -ForegroundColor Gray
    Write-Host ""
    
    # Показываем fingerprint
    $fingerprint = ssh-keygen -lf $KeyPath 2>&1
    Write-Host "  Fingerprint: $fingerprint" -ForegroundColor Gray
    Write-Host ""
    
    return $true
}

# Export-ModuleMember используется только при импорте как модуля
# При dot-sourcing (. script.ps1) функции становятся доступными автоматически

