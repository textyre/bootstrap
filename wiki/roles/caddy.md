# Caddy Role

The `caddy` role provides the shared Docker-based HTTP/HTTPS entry point for
self-hosted applications. It owns the Caddy Compose project, external proxy
network, global configuration and server-side trust for Caddy's internal CA.

Application roles own files below `/opt/caddy/sites/`. Docker owns the engine,
the firewall owns inbound ports, name-resolution infrastructure owns DNS and
each client device owns its certificate trust. Those concerns are not changed
by this role.

## TLS modes

| Mode | Behavior |
|---|---|
| `internal` | Caddy creates a local CA and the role installs its root certificate into the server trust store |
| `acme` | Caddy requests publicly trusted certificates using the configured account email |

The package layer supplies the host CA trust tools. In internal mode the role
uses the certificate already present in Caddy's bind-mounted data directory and
rebuilds the host trust database only when that certificate changes.

## Execution

The pipeline is `validate -> configure -> service -> trust -> report`.
Configuration is split into network, directories, global Caddyfile and Compose
project responsibilities. A checksum label in the Compose service description
makes global Caddyfile changes part of the desired container state; there are no
Caddy handlers or unconditional restart tasks.

Molecule runs Arch and Ubuntu in privileged systemd containers with a nested
Docker daemon and in full VMs. Both scenarios check syntax, convergence and
idempotence without duplicating Compose or Caddy runtime behavior checks.
