import { chmod, cp, mkdir, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repositoryDir = path.resolve(projectDir, '..');
const distDir = path.join(projectDir, 'dist');
const artifactFile = path.join(distDir, 'ctos-greeter.tar');
const themeBuildDir = path.join(distDir, 'theme');
const rootfsDir = path.join(distDir, 'rootfs');
const themeDir = path.join(rootfsDir, 'usr/share/web-greeter/themes/ctos');
const helperDir = path.join(rootfsDir, 'usr/lib/ctos-greeter');
const lightdmConfigDir = path.join(rootfsDir, 'etc/lightdm');
const lightdmDropInDir = path.join(lightdmConfigDir, 'lightdm.conf.d');

async function normalizePermissions(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      await chmod(entryPath, 0o755);
      await normalizePermissions(entryPath);
    } else {
      await chmod(entryPath, 0o644);
    }
  }
}

await rm(rootfsDir, { recursive: true, force: true });
await Promise.all([
  mkdir(path.dirname(themeDir), { recursive: true }),
  mkdir(helperDir, { recursive: true }),
  mkdir(lightdmDropInDir, { recursive: true }),
]);

await rename(themeBuildDir, themeDir);
await Promise.all([
  cp(path.join(projectDir, 'index.yml'), path.join(themeDir, 'index.yml')),
  cp(path.join(repositoryDir, 'dotfiles/wallpapers'), path.join(themeDir, 'backgrounds'), {
    recursive: true,
  }),
  cp(
    path.join(projectDir, 'config/web-greeter.yml'),
    path.join(lightdmConfigDir, 'web-greeter.yml'),
  ),
  cp(
    path.join(projectDir, 'config/20-ctos-greeter.conf'),
    path.join(lightdmDropInDir, '20-ctos-greeter.conf'),
  ),
  cp(
    path.join(projectDir, 'scripts/write-system-info.mjs'),
    path.join(helperDir, 'write-system-info'),
  ),
]);

const packageMetadata = JSON.parse(await readFile(path.join(projectDir, 'package.json'), 'utf8'));
await writeFile(path.join(themeDir, 'version'), `${packageMetadata.version}\n`, { mode: 0o644 });
await normalizePermissions(rootfsDir);
await chmod(path.join(helperDir, 'write-system-info'), 0o755);

const artifactEntries = (await readdir(rootfsDir)).sort();
await rm(artifactFile, { force: true });
execFileSync('tar', [
  '--create',
  '--file', artifactFile,
  '--owner=0',
  '--group=0',
  '--numeric-owner',
  '--directory', rootfsDir,
  ...artifactEntries,
]);
await rm(rootfsDir, { recursive: true, force: true });
