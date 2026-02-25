# Claudette Agent Memory - Bootstrap Project

## Окружение разработки

### Supergrep MCP (Windows)
- [ ] `.mcp.json` команда: `supergrep` (через shim в `D:\AppData\Local\nvm\supergrep.cmd`)
- [ ] Shim указывает на: `node D:/projects/supergrep/dist/cli/index.js mcp-serve`
- [ ] НЕ переопределять `nvm` в PowerShell profile
- [ ] `.mcp.json` должен быть валидным JSON (дублирование блоков ломало)

## Ansible — соглашения по ролям

### Стиль кода
- [ ] Комментарии на русском, заголовки секций: `# ---- Раздел ----`
- [ ] Шапка файла: `# === Название роли ===`
- [ ] Префикс переменных = имя роли: `docker_*`, `caddy_*`
- [ ] Теги: имя роли + функциональные (`configure`, `service`)
- [ ] FQCN для всех модулей: `ansible.builtin.file`, `community.docker.*`
- [ ] Handlers: `listen:` для кросс-ролевых уведомлений


