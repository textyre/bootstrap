# greeter

Deploys the released ctOS greeter artifact from the standalone
[textyre/ctos-greeter](https://github.com/textyre/ctos-greeter) repository.

## Contract

The role has one responsibility: download the pinned release artifact and
deploy it onto the target host. It does not build the frontend, interpret the
artifact contents, collect machine information, or configure individual
greeter features.

The artifact owns everything required by the ctOS greeter, including its theme,
runtime configuration, metadata, and machine-information helper.
The `packages` and `lightdm` roles remain responsible for installing the greeter
runtime and managing the display manager.
The ctOS system-information helper uses `/usr/bin/env node`. On Arch that is the
newest stable Node from nvm, linked as `/usr/local/bin/node` by the `nvm` role;
elsewhere the `packages_session` list installs `nodejs`.

## nody-greeter (Arch)

The role builds nody-greeter from the AUR itself. nody-greeter is no longer
developed and is Electron 27, which builds only with Node 20 or older (`nodejs<21`),
and no pacman package provides that Node any more. The build user (`aur_builder`)
gets Node `greeter_nody_build_node` (20) from nvm, `makepkg --nodeps` builds the
package with it, pacman installs the result, and that Node is removed again
(`greeter_nody_keep_build_node: false`). The installed greeter runs on Electron's
own Node. A package already at `greeter_nody_package_version` is not rebuilt.

## Execution flow

1. **Deploy** - download the release tar (checksum-verified) and extract it
   onto the target filesystem. When the theme directory came from another
   artifact (the checksum in `greeter_artifact_marker` differs), it is removed
   first, so no files of the older theme stay behind.
2. **Report** - record that the ctOS greeter artifact was deployed.

The role has no handlers, platform branches, or init-system branches.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `greeter_version` | `1.0.1-rc.2` | Released ctos-greeter version to deploy. |
| `greeter_artifact_url` | GitHub Release URL derived from `greeter_version` | Download location of `ctos-greeter.tar`. |
| `greeter_artifact_checksum` | pinned `sha256:...` | Checksum the downloaded artifact must match. |
| `greeter_theme_dir` | `/usr/share/web-greeter/themes/ctos` | The theme directory, replaced whole when the artifact changes. |
| `greeter_artifact_marker` | `/usr/lib/ctos-greeter/artifact` | File holding the checksum of the deployed artifact. |

Bumping the version requires updating both `greeter_version` and
`greeter_artifact_checksum` together.

## Machine information

Machine information displayed on the login screen belongs to the greeter
artifact. Its LightDM setup helper refreshes `system-info.json` when the greeter
starts. Ansible does not collect or render those values.

## Testing

Docker and Vagrant scenarios run on Arch Linux and Ubuntu. Each scenario
converges the role with its defaults, downloading the pinned release artifact
from GitHub, and runs the idempotence pass. The tests cover artifact
deployment; installing Nody and starting LightDM belong to their respective
role and workstation integration tests.

Ansible, Molecule, package, and build commands run only on the remote VM or in
CI.

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Download fails | Release or network unavailable from the target | Check `greeter_artifact_url` and network access; releases are published by the ctos-greeter repository CI. |
| Checksum mismatch | `greeter_version` and `greeter_artifact_checksum` are out of sync | Update both values together from the release. |
