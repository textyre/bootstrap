#!/bin/bash
# Manual Arch Linux installation — run from live ISO as root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bootstrap-env.sh"

bootstrap_require_var "BOOTSTRAP_INSTALL_DISK"
bootstrap_require_var "BOOTSTRAP_INSTALL_USERNAME"
bootstrap_require_var "BOOTSTRAP_INSTALL_HOSTNAME"
bootstrap_require_file "BOOTSTRAP_SSH_PUBLIC_KEY_FILE"

DISK="${BOOTSTRAP_INSTALL_DISK}"
INSTALL_USER="${BOOTSTRAP_INSTALL_USERNAME}"
INSTALL_HOSTNAME="${BOOTSTRAP_INSTALL_HOSTNAME}"
INSTALL_TIMEZONE="${BOOTSTRAP_INSTALL_TIMEZONE:-UTC}"
INSTALL_LOCALE="${BOOTSTRAP_INSTALL_LOCALE:-en_US.UTF-8}"
SSH_PUB="$(tr -d '\r\n' < "${BOOTSTRAP_SSH_PUBLIC_KEY_FILE}")"
ROOT_PASS="$(bootstrap_root_password)"
USER_PASS="$(bootstrap_user_password)"

echo "==> Partitioning ${DISK}..."
parted "${DISK}" --script mklabel msdos mkpart primary ext4 1MiB 100% set 1 boot on

echo "==> Formatting..."
mkfs.ext4 -F "${DISK}1"

echo "==> Mounting..."
mount "${DISK}1" /mnt

echo "==> pacstrap..."
pacstrap /mnt base base-devel linux linux-firmware grub openssh sudo wget curl

echo "==> fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Configuring in chroot..."
arch-chroot /mnt env \
  INSTALL_HOSTNAME="${INSTALL_HOSTNAME}" \
  INSTALL_TIMEZONE="${INSTALL_TIMEZONE}" \
  INSTALL_LOCALE="${INSTALL_LOCALE}" \
  INSTALL_USER="${INSTALL_USER}" \
  ROOT_PASS="${ROOT_PASS}" \
  USER_PASS="${USER_PASS}" \
  SSH_PUB="${SSH_PUB}" \
  INSTALL_DISK="${DISK}" \
  /bin/bash <<'EOF'
set -e
echo "${INSTALL_HOSTNAME}" > /etc/hostname
ln -sf "/usr/share/zoneinfo/${INSTALL_TIMEZONE}" /etc/localtime
hwclock --systohc
echo "${INSTALL_LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${INSTALL_LOCALE}" > /etc/locale.conf
printf 'root:%s\n' "${ROOT_PASS}" | chpasswd
useradd -m -G wheel -s /bin/bash "${INSTALL_USER}"
printf '%s:%s\n' "${INSTALL_USER}" "${USER_PASS}" | chpasswd
mkdir -p "/home/${INSTALL_USER}/.ssh"
printf '%s\n' "${SSH_PUB}" > "/home/${INSTALL_USER}/.ssh/authorized_keys"
chmod 700 "/home/${INSTALL_USER}/.ssh"
chmod 600 "/home/${INSTALL_USER}/.ssh/authorized_keys"
chown -R "${INSTALL_USER}:${INSTALL_USER}" "/home/${INSTALL_USER}/.ssh"
systemctl enable sshd
grub-install --target=i386-pc "${INSTALL_DISK}"
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "==> Install complete! Rebooting..."
reboot
