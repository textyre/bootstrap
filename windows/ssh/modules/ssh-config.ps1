# ============================================
# МОДУЛЬ: Обновление SSH конфигурации
# ============================================
# Добавляет запись в ~/.ssh/config для удобного подключения

function Update-SSHConfig {
    param(
        [string]$ConfigPath,
        [string]$HostAlias,
        [string]$ServerHost,
        [int]$ServerPort,
        [string]$ServerUser,
        [string]$KeyPath
    )
    
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Обновление SSH конфигурации" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Создаем директорию если не существует
    $configDir = Split-Path -Parent $ConfigPath
    if (!(Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }
    
    # Формируем запись для конфига
    $configEntry = @"

# Arch Linux server - автоматически создано $(Get-Date -Format "yyyy-MM-dd HH:mm")
Host $HostAlias
    HostName $ServerHost
    Port $ServerPort
    User $ServerUser
    IdentityFile $KeyPath
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new

"@
    
    # Проверяем существование конфига
    if (Test-Path $ConfigPath) {
        $existingConfig = Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue
        
        # Проверяем, есть ли уже запись для этого хоста
        if ($existingConfig -match "Host $HostAlias\s") {
            Write-Host "ℹ Запись для хоста '$HostAlias' уже существует" -ForegroundColor Yellow
            Write-Host ""
            
            $response = Read-Host "Обновить запись? (y/N)"
            if ($response -eq "y" -or $response -eq "Y") {
                # Удаляем старую запись (блок от Host до следующего Host или конца файла)
                $pattern = "(?ms)^# Arch Linux server.*?^Host $HostAlias\s.*?(?=^Host |\z)"
                $existingConfig = $existingConfig -replace $pattern, ""
                Set-Content -Path $ConfigPath -Value $existingConfig.TrimEnd()
                Add-Content -Path $ConfigPath -Value $configEntry
                Write-Host "✓ SSH config обновлен" -ForegroundColor Green
            } else {
                Write-Host "✓ SSH config оставлен без изменений" -ForegroundColor Green
            }
        } else {
            # Добавляем новую запись
            Add-Content -Path $ConfigPath -Value $configEntry
            Write-Host "✓ SSH config обновлен" -ForegroundColor Green
        }
    } else {
        # Создаем новый конфиг
        Set-Content -Path $ConfigPath -Value $configEntry.TrimStart()
        Write-Host "✓ SSH config создан" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Теперь можно подключаться просто:" -ForegroundColor Yellow
    Write-Host "  ssh $HostAlias" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Или полной командой:" -ForegroundColor Yellow
    Write-Host "  ssh -i `"$KeyPath`" -p $ServerPort $ServerUser@$ServerHost" -ForegroundColor Gray
    Write-Host ""
    
    return $true
}

# Функция для отображения существующих хостов
function Show-SSHHosts {
    param([string]$ConfigPath)
    
    if (!(Test-Path $ConfigPath)) {
        Write-Host "SSH config не найден" -ForegroundColor Gray
        return
    }
    
    $config = Get-Content $ConfigPath -Raw
    $sshHosts = [regex]::Matches($config, '(?m)^Host\s+(.+?)$') | ForEach-Object { $_.Groups[1].Value }
    
    if ($sshHosts.Count -gt 0) {
        Write-Host "Настроенные хосты в SSH config:" -ForegroundColor Cyan
        foreach ($hostName in $sshHosts) {
            Write-Host "  • $hostName" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

# Export-ModuleMember используется только при импорте как модуля
# При dot-sourcing (. script.ps1) функции становятся доступными автоматически

