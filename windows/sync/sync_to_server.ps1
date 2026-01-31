<# ============================================
   СИНХРОНИЗАЦИЯ ПРОЕКТА С ARCH СЕРВЕРОМ
   Обновляет только измененные файлы (rsync) или полную копию (scp)
   ============================================ #>

[CmdletBinding()]
param(
    [switch]$ForceScp,
    [switch]$SkipPermissions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StartTime = Get-Date
$script:sshAuthArgs = @()
$script:sshHost = ""
$script:sshPort = ""

function ConvertTo-PosixLiteral {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $escaped = [Regex]::Replace($Value, '(["\\$`])', '\\$1')
    return ('"{0}"' -f $escaped)
}

function Format-CommandPart {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value -match '\s') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function Get-SshArgs {
    param(
        [string[]]$Tail = @()
    )

    $args = @()
    if ($script:sshAuthArgs.Count -gt 0) {
        $args += $script:sshAuthArgs
    }

    $args += @("-p", $script:sshPort)

    if ($Tail.Count -gt 0) {
        $args += $Tail
    }

    return $args
}

function Get-ScpArgs {
    param(
        [switch]$Recurse
    )

    $args = @()
    if ($script:sshAuthArgs.Count -gt 0) {
        $args += $script:sshAuthArgs
    }

    $args += @("-P", $script:sshPort, "-p")

    if ($Recurse.IsPresent) {
        $args += "-r"
    }

    return $args
}

function Get-RsyncTransport {
    $parts = @("ssh")

    if ($script:sshAuthArgs.Count -gt 0) {
        foreach ($part in $script:sshAuthArgs) {
            $parts += (Format-CommandPart -Value $part)
        }
    }

    $parts += "-p"
    $parts += $script:sshPort

    return ($parts -join ' ')
}

function Invoke-SSHCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    $args = Get-SshArgs -Tail @($script:sshHost, $Command)
    Write-Verbose ("ssh {0}" -f ($args -join ' '))
    & ssh @args
    return $LASTEXITCODE
}

try {
    . "$PSScriptRoot\..\config\config.ps1"

    $script:sshPort = [string]$Global:SERVER_PORT
    $script:sshHost = "$($Global:SERVER_USER)@$($Global:SERVER_HOST)"

    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║      СИНХРОНИЗАЦИЯ С ARCH СЕРВЕРОМ       ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Config)) {
        throw "Ошибка в конфигурации. Проверьте файл config\config.ps1"
    }

    $sshCmd = Get-Command ssh -ErrorAction SilentlyContinue
    if (-not $sshCmd) {
        throw "Команда ssh не найдена. Установите OpenSSH (Apps -> Optional Features) и повторите."
    }

    $syncSourceInfo = Get-Item -LiteralPath $Global:SYNC_SOURCE_DIR -ErrorAction Stop
    # Collect all files within the whitelist items
    $syncFiles = @()
    foreach ($item in $Global:SYNC_ITEMS) {
        $itemPath = Join-Path -Path $syncSourceInfo.FullName -ChildPath $item
        if (Test-Path -LiteralPath $itemPath) {
            if ((Get-Item -LiteralPath $itemPath).PSIsContainer) {
                $syncFiles += Get-ChildItem -LiteralPath $itemPath -Recurse -File
            } else {
                $syncFiles += Get-Item -LiteralPath $itemPath
            }
        }
    }

    Write-Host "Локальная папка:  $($syncSourceInfo.FullName)" -ForegroundColor Yellow
    Write-Host "Найдено файлов:   $($syncFiles.Count)" -ForegroundColor Yellow
    Write-Host ("Удаленный сервер: {0}:{1}" -f $script:sshHost, $script:sshPort) -ForegroundColor Yellow
    Write-Host "Удаленный путь:   $($Global:REMOTE_PATH)" -ForegroundColor Yellow
    Write-Host ""

    $sshKeyExists = Test-Path -LiteralPath $Global:SSH_KEY
    if ($sshKeyExists) {
        Write-Host "✓ Используется SSH ключ: $($Global:SSH_KEY)" -ForegroundColor Green
        $script:sshAuthArgs = @("-i", $Global:SSH_KEY)
    } else {
        Write-Host "⚠ SSH ключ не найден: $($Global:SSH_KEY)" -ForegroundColor Yellow
        Write-Host "  Запустите .\ssh\setup_ssh_key.ps1 для автоматической настройки." -ForegroundColor Yellow
        Write-Host ""
        $response = Read-Host "Продолжить с паролем? (y/N)"
        if ($response -notin @("y", "Y")) {
            throw "Операция отменена пользователем."
        }
    }

    $remotePathLiteral = ConvertTo-PosixLiteral -Value $Global:REMOTE_PATH

    Write-Host "Проверяю доступность сервера..." -ForegroundColor Cyan
    $tcpTest = Test-NetConnection -ComputerName $Global:SERVER_HOST -Port $Global:SERVER_PORT -WarningAction SilentlyContinue
    if (-not $tcpTest.TcpTestSucceeded) {
        throw ("SSH сервер недоступен ({0}:{1}). Убедитесь, что виртуальная машина запущена и проброс портов настроен." -f $Global:SERVER_HOST, $Global:SERVER_PORT)
    }
    Write-Host "✓ Сервер доступен" -ForegroundColor Green

    Write-Host "Проверяю/создаю удаленную директорию..." -ForegroundColor Cyan
    if ((Invoke-SSHCommand -Command ("mkdir -p {0}" -f $remotePathLiteral)) -ne 0) {
        throw "Не удалось создать директорию $($Global:REMOTE_PATH) на сервере."
    }
    Write-Host "✓ Каталог готов" -ForegroundColor Green
    Write-Host ""

    $rsyncCmd = $null
    if (-not $ForceScp.IsPresent) {
        $rsyncCmd = Get-Command rsync -ErrorAction SilentlyContinue
    }

    $syncUsed = ""

    if ($rsyncCmd) {
        Write-Host "Используем rsync (только изменения, с удалением лишнего)..." -ForegroundColor Cyan

        $localPath = $syncSourceInfo.FullName -replace '\\', '/'
        if (-not $localPath.EndsWith('/')) {
            $localPath += '/'
        }

        $remotePathClean = ($Global:REMOTE_PATH.TrimEnd('/'))
        $remotePathEscaped = $remotePathClean.Replace('"', '\"')
        $remoteTarget = "{0}:`"{1}/`"" -f $script:sshHost, $remotePathEscaped

        $rsyncArgs = @(
            "-avz",
            "--delete",
            "--human-readable",
            "--info=stats2"
        )

        foreach ($item in $Global:SYNC_ITEMS) {
            $itemPath = Join-Path -Path $syncSourceInfo.FullName -ChildPath $item
            if (Test-Path -LiteralPath $itemPath) {
                if ((Get-Item -LiteralPath $itemPath).PSIsContainer) {
                    $rsyncArgs += @("--include", "/$item/", "--include", "/$item/**")
                } else {
                    $rsyncArgs += @("--include", "/$item")
                }
            }
        }
        $rsyncArgs += @("--exclude", "*")

        $rsyncArgs += @("-e", (Get-RsyncTransport))
        $rsyncArgs += @($localPath, $remoteTarget)

        Write-Verbose ("rsync {0}" -f ($rsyncArgs -join ' '))
        & rsync @rsyncArgs

        if ($LASTEXITCODE -ne 0) {
            throw "rsync завершился с ошибкой (код $LASTEXITCODE)."
        }

        $syncUsed = "rsync"
        Write-Host "✓ Синхронизация через rsync завершена" -ForegroundColor Green
    } else {
        Write-Host "rsync недоступен. Переключаемся на scp (копируется весь проект)..." -ForegroundColor Yellow
        Write-Host "Подсказка: winget install rsync  # чтобы включить режим обновления только изменений" -ForegroundColor Gray
        Write-Host ""

        $scpCmd = Get-Command scp -ErrorAction SilentlyContinue
        if (-not $scpCmd) {
            throw "Команда scp не найдена. Установите OpenSSH Client и повторите."
        }

        if ($syncFiles.Count -eq 0) {
            throw "В белом списке SYNC_ITEMS не найдено файлов для копирования."
        }

        $remoteBase = "{0}:{1}/" -f $script:sshHost, $Global:REMOTE_PATH.TrimEnd('/')

        foreach ($item in $Global:SYNC_ITEMS) {
            $itemPath = Join-Path -Path $syncSourceInfo.FullName -ChildPath $item
            if (-not (Test-Path -LiteralPath $itemPath)) {
                Write-Host "  Пропускаю (не найден): $item" -ForegroundColor Gray
                continue
            }

            $isDir = (Get-Item -LiteralPath $itemPath).PSIsContainer
            $scpArgs = if ($isDir) { Get-ScpArgs -Recurse } else { Get-ScpArgs }
            $scpArgs += $itemPath
            $scpArgs += $remoteBase

            Write-Verbose ("scp {0}" -f ($scpArgs -join ' '))
            & scp @scpArgs

            if ($LASTEXITCODE -ne 0) {
                throw "scp завершился с ошибкой при копировании '$item' (код $LASTEXITCODE)."
            }

            Write-Host "  ✓ $item" -ForegroundColor Green
        }

        $syncUsed = "scp"
        Write-Host "✓ Файлы скопированы через scp" -ForegroundColor Green
    }

    if (-not $SkipPermissions.IsPresent) {
        Write-Host ""
        Write-Host "Выставляю права на выполнение и исправляю окончания строк (*.sh)..." -ForegroundColor Cyan
        # Нормализуем окончания строк (CRLF -> LF) с помощью sed, затем рекурсивно выставим бит +x
        # sed присутствует почти на всех Unix-системах; если его нет, просто выполнится chmod
        $findCommand = "if command -v sed >/dev/null 2>&1; then find {0} -type f -name '*.sh' -exec sed -i 's/\r$//' {{}} +; fi; find {0} -type f -name '*.sh' -exec chmod +x {{}} +" -f $remotePathLiteral
        if ((Invoke-SSHCommand -Command $findCommand) -ne 0) {
            throw "Не удалось обновить права/выполнить патчинг .sh файлов в $($Global:REMOTE_PATH)."
        }
        Write-Host "✓ Права обновлены и патчинг выполнен" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Пропускаю установку прав (флаг -SkipPermissions)" -ForegroundColor Gray
    }

    $duration = (Get-Date) - $script:StartTime
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║            ✓ ГОТОВО!                     ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host ("Метод синхронизации: {0}" -f $syncUsed.ToUpperInvariant()) -ForegroundColor Gray
    Write-Host ("Обновлено файлов:   {0}" -f $syncFiles.Count) -ForegroundColor Gray
    Write-Host ("Время выполнения:   {0:N1} с" -f $duration.TotalSeconds) -ForegroundColor Gray
    Write-Host ""
    Write-Host "Актуальные команды на сервере:" -ForegroundColor Yellow
    $sshSample = if ($sshKeyExists) {
        "ssh -i `"$($Global:SSH_KEY)`" -p $($Global:SERVER_PORT) $script:sshHost"
    } else {
        "ssh -p $($Global:SERVER_PORT) $script:sshHost"
    }
    Write-Host ("  {0}" -f $sshSample) -ForegroundColor Gray
    Write-Host ("  cd {0}" -f $Global:REMOTE_PATH) -ForegroundColor Gray
    Write-Host "  ./bootstrap.sh" -ForegroundColor Gray
    Write-Host "  ./bin/show-installed-packages.sh" -ForegroundColor Gray
    Write-Host "  ./bin/show-all-dependencies.sh" -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "✗ Синхронизация завершилась с ошибкой" -ForegroundColor Red
    Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
