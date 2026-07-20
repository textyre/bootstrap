# ctOS Greeter Design

## Purpose

ctOS uses a custom web login experience on top of LightDM and Nody Greeter. The
frontend is a Vite/TypeScript application that authenticates through the
greeter-provided LightDM JavaScript API; it does not implement PAM itself.

## Ownership

| Component | Owner |
|-----------|-------|
| LightDM, Nody Greeter, Xorg packages | `packages` role |
| X11 keyboard and monitor state | `xorg` role |
| Complete deployable greeter artifact | `greeter/` project |
| Greeter artifact deployment | `greeter` role |
| Enabled and running display manager | `lightdm` role |

The workstation pipeline builds the frontend, deploys `greeter`, and starts
`lightdm` afterward. This order prevents LightDM from launching an incomplete
theme during initial provisioning.

## Build and deployment

`task greeter:build` runs `npm ci` and `npm run build` in `greeter/`. The build
creates the complete filesystem artifact in `greeter/dist/rootfs`. The role
copies that artifact onto the target without interpreting its contents.

The artifact owns the theme, Nody configuration, backgrounds, metadata, and a
LightDM setup helper. The helper refreshes host, kernel, virtualization,
timezone, display, and SSH fingerprint data when the greeter starts.
Hardware-dependent values use `unknown` when the corresponding device or key is
absent.

## Security boundary

- Secure mode is enabled by default.
- Deployed artifact files are owned by `root:root`.
- The frontend receives public host metadata only; no credentials or private keys are copied.
- Authentication remains inside LightDM/PAM through the Nody API.

## Test boundary

CI builds the real frontend before Docker and Vagrant Molecule scenarios. Those
scenarios prove deterministic deployment and idempotence on Arch Linux and
Ubuntu. Rendering and authentication require the integrated graphical
workstation pipeline and are not simulated with fake HTML or a fake LightDM API.
