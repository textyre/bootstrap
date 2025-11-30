# ============================================
# МОДУЛЬ: Копирование SSH ключа на сервер
# ============================================
# Отправляет публичный ключ на удаленный сервер

function Copy-SSHKey {
    param(
        [string]$PublicKeyPath,
        [string]$ServerUser,
        [string]$ServerHost,
        [int]$ServerPort
    )
    
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Копирование ключа на сервер" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Проверяем существование публичного ключа
    if (!(Test-Path $PublicKeyPath)) {
        Write-Host "✗ Публичный ключ не найден: $PublicKeyPath" -ForegroundColor Red
        return $false
    }
    
    Write-Host "Сервер: $ServerUser@${ServerHost}:$ServerPort" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "⚠ Вам нужно будет ввести пароль В ПОСЛЕДНИЙ РАЗ" -ForegroundColor Yellow
    Write-Host ""
    
    # Читаем публичный ключ
    try {
        $pubKey = Get-Content $PublicKeyPath -Raw
        $pubKey = $pubKey.Trim()
    } catch {
        Write-Host "✗ Ошибка чтения публичного ключа" -ForegroundColor Red
        return $false
    }
    
    # Создаем команду для добавления ключа
    $command = @"
mkdir -p ~/.ssh && \
chmod 700 ~/.ssh && \
echo '$pubKey' >> ~/.ssh/authorized_keys && \
chmod 600 ~/.ssh/authorized_keys && \
sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && \
echo 'SSH key added successfully'
"@
    
    Write-Host "Подключаюсь к серверу..." -ForegroundColor Cyan
    
    # Отправляем ключ
    $result = ssh -p $ServerPort "$ServerUser@$ServerHost" $command 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✓ Публичный ключ успешно скопирован на сервер!" -ForegroundColor Green
        Write-Host ""
        return $true
    } else {
        Write-Host ""
        Write-Host "✗ Ошибка при копировании ключа" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
        Write-Host ""
        Write-Host "Попробуйте вручную:" -ForegroundColor Yellow
        Write-Host "  type `"$PublicKeyPath`" | ssh -p $ServerPort $ServerUser@$ServerHost `"cat >> ~/.ssh/authorized_keys`"" -ForegroundColor Gray
        Write-Host ""
        return $false
    }
}

# Функция для проверки подключения
function Test-SSHConnection {
    param(
        [string]$KeyPath,
        [string]$ServerUser,
        [string]$ServerHost,
        [int]$ServerPort
    )
    
    Write-Host "Тестирую подключение без пароля..." -ForegroundColor Cyan
    
    $testResult = ssh -i $KeyPath -p $ServerPort -o "BatchMode=yes" -o "StrictHostKeyChecking=no" "$ServerUser@$ServerHost" "echo 'Connection OK'" 2>&1
    
    if ($LASTEXITCODE -eq 0 -and $testResult -match "Connection OK") {
        Write-Host "✓ Подключение без пароля работает отлично!" -ForegroundColor Green
        Write-Host ""
        return $true
    } else {
        Write-Host "⚠ Проблемы с подключением без пароля" -ForegroundColor Yellow
        Write-Host "  Возможно, нужно подтвердить fingerprint сервера" -ForegroundColor Gray
        Write-Host ""
        return $false
    }
}

# Export-ModuleMember используется только при импорте как модуля
# При dot-sourcing (. script.ps1) функции становятся доступными автоматически

