# caddy

Runs Caddy in Docker as the shared HTTP/HTTPS reverse proxy for self-hosted
services.

## Contract

The role requires an installed and running Docker Engine, Compose V2 and the
Python dependency used by `community.docker`. In `internal` mode, the package
layer must also provide the host `ca-certificates` package. The role:

- creates the external Docker network shared with proxied applications;
- creates the Caddy configuration and writable data directories;
- deploys the global Caddyfile and Compose project;
- keeps the Caddy Compose project present;
- imports application-owned `sites/*.caddy` files;
- installs Caddy's root certificate into the host trust store in `internal`
  TLS mode.

Application roles own their individual site files. Docker, firewall, DNS and
client-device trust remain outside this role. Installing the root certificate
on the server does not distribute it to other devices.

## Pipeline

`validate -> configure -> service -> trust -> report`

`configure` is split into the Docker network, directories, global Caddyfile and
Compose project. The rendered global configuration checksum is part of the
Compose service description, so `docker_compose_v2` recreates the container
when that configuration changes. No handler or unconditional restart is used.

In `internal` mode, Caddy writes its local root certificate into the bind-mounted
data directory. The role copies that host file to the distribution trust source
and rebuilds the host trust database only when the certificate changes.

## Variables

| Variable | Default | Meaning |
|---|---:|---|
| `caddy_base_dir` | `/opt/caddy` | Compose, site, data and state root |
| `caddy_container_uid` | `100000` | Host UID/GID mapped to container root by Docker userns-remap |
| `caddy_https_port` | `443` | Published HTTPS port |
| `caddy_http_port` | `80` | Published HTTP port |
| `caddy_tls_mode` | `internal` | `internal` local CA or public `acme` certificates |
| `caddy_tls_email` | empty | ACME account email, required in `acme` mode |
| `caddy_docker_network` | `proxy` | External network shared with application containers |
| `caddy_docker_image` | `caddy:2.11.4-alpine` | Pinned Caddy container image |

Changing `caddy_base_dir` or `caddy_container_uid` on an existing installation
requires a matching data migration. ACME mode requires a publicly registrable
domain and successful ACME validation outside this role. The configured host
ports must be free before the Compose project starts.

## Platforms

The role has trust-store mappings for Arch Linux, Ubuntu/Debian, Fedora, Void
and Gentoo. Caddy itself runs in Docker and is independent of the host init
system.

## Tests

`task test-caddy` runs Docker and Vagrant scenarios on Arch and Ubuntu. The
Docker scenario provides privileged systemd containers with a real nested
Docker daemon; Vagrant provides full VMs. Both prepare only the external Docker,
Compose and CA-package prerequisites, then check syntax, convergence and
idempotence. The scenarios use internal TLS; they do not claim to test public
ACME certificate issuance.

All Ansible and Molecule operations run through the project's remote VM and
Taskfile workflow.
