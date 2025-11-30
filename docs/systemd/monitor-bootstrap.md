---
title: "Systemd: monitor-bootstrap.service"
type: guide
entities: [systemd, service]
created: 2025-11-30
authors: [docs-team]
tags: [systemd, service, monitor, display-manager]
---

# Systemd unit для применения режима перед display-manager

Файл `/etc/systemd/system/monitor-bootstrap.service` (пример):

```
[Unit]
Description=Apply monitor mode before display manager
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/monitor-bootstrap.sh
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
```

Команды для установки/включения (документация):

```
sudo chmod +x /usr/local/bin/monitor-bootstrap.sh
sudo systemctl daemon-reload
sudo systemctl enable --now monitor-bootstrap.service
sudo systemctl restart lightdm
```

Примечание: сам скрипт рекомендуется хранить в `scripts/` и только документировать
его здесь; этот файл — описание юнита и ожидаемого поведения.
