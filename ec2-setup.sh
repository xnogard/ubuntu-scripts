#!/usr/bin/env bash
#
# AWS EC2 Ubuntu setup script
# - Sets up a user account with password
# - Enables password-based SSH login
# - Configures UFW firewall + Fail2Ban
# - Optional: Apache + PHP, Webmin, ZeroTier
#
# WARNING: Enabling password authentication reduces security compared to key-only.
# Use a strong password and keep the Security Group + UFW restricted where possible.
#
# Usage (after first key-based login):
#   curl -fsSL <url-to-this-script> -o setup.sh && bash setup.sh
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Must run as root or with sudo
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo bash "$0" "$@"
  else
    error "Please run as root or with sudo."
  fi
fi

# Detect OS
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  error "Cannot detect OS. This script targets Ubuntu/Debian."
fi

if [[ "${ID}" != "ubuntu" && "${ID}" != "debian" ]]; then
  warn "This script is optimized for Ubuntu/Debian. Continuing anyway..."
fi

info "Detected: ${PRETTY_NAME:-$ID $VERSION_ID}"

# --- Update system ---
info "Updating package lists and upgrading packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl wget gnupg ca-certificates software-properties-common unzip

# --- User setup ---
echo
info "=== User Account Setup ==="
read -rp "Enter username to set up (default: ${SUDO_USER:-ubuntu}): " USERNAME
USERNAME=${USERNAME:-${SUDO_USER:-ubuntu}}

if id "$USERNAME" &>/dev/null; then
  info "User '$USERNAME' already exists."
else
  info "Creating user '$USERNAME'..."
  adduser --gecos "" --disabled-password "$USERNAME" || error "Failed to create user"
fi

if ! groups "$USERNAME" | grep -q '\bsudo\b'; then
  usermod -aG sudo "$USERNAME"
  info "Added '$USERNAME' to sudo group."
fi

echo
warn "You will now set a password for '$USERNAME'."
warn "Choose a strong password. This will be used for SSH login."
passwd "$USERNAME" || error "Failed to set password"

# --- Enable password SSH auth ---
info "Configuring SSH to allow password authentication..."
SSH_DROPIN="/etc/ssh/sshd_config.d/01-password-auth.conf"
cat > "$SSH_DROPIN" << 'EOFCONF'
# Enable password authentication (created by ec2-setup script)
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
EOFCONF

if sshd -t 2>/dev/null; then
  info "SSH config test passed."
else
  warn "SSH config test had warnings. Review with: sshd -t"
fi

systemctl restart ssh || systemctl restart sshd || warn "Could not restart SSH service."
info "SSH password authentication enabled."

# --- UFW Firewall ---
echo
info "=== Configuring UFW Firewall ==="
apt-get install -y -qq ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
info "UFW: default deny incoming, allow outgoing, allow SSH (22/tcp)"

# --- Fail2Ban ---
echo
info "=== Configuring Fail2Ban ==="
apt-get install -y -qq fail2ban

# Local jail config (overrides defaults)
cat > /etc/fail2ban/jail.local << 'EOFJAIL'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOFJAIL

systemctl enable --now fail2ban
info "Fail2Ban installed and enabled for SSH (ban after 5 failures in 10 minutes)."

# --- Optional packages ---
echo
info "=== Optional Software ==="

read -rp "Install Apache + PHP? (y/N): " INSTALL_WEB
INSTALL_WEB=${INSTALL_WEB:-n}
if [[ "${INSTALL_WEB,,}" == "y" ]]; then
  info "Installing Apache and PHP..."
  apt-get install -y apache2 php libapache2-mod-php php-cli php-mysql php-curl php-gd php-mbstring php-xml php-zip
  systemctl enable --now apache2
  ufw allow 'Apache Full' comment 'HTTP/HTTPS' || ufw allow 80,443/tcp
  info "Apache + PHP installed. Ports 80/443 allowed in UFW."
fi

read -rp "Install Webmin (web admin panel on port 10000)? (y/N): " INSTALL_WEBMIN
INSTALL_WEBMIN=${INSTALL_WEBMIN:-n}
if [[ "${INSTALL_WEBMIN,,}" == "y" ]]; then
  info "Installing Webmin..."
  curl -fsSL -o /tmp/webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
  bash /tmp/webmin-setup-repo.sh
  apt-get update -qq
  apt-get install -y --install-recommends webmin
  systemctl enable --now webmin || true
  ufw allow 10000/tcp comment 'Webmin'
  info "Webmin installed. Port 10000 allowed in UFW."
  info "Access at https://<your-ip>:10000"
fi

read -rp "Install ZeroTier (VPN mesh)? (y/N): " INSTALL_ZT
INSTALL_ZT=${INSTALL_ZT:-n}
if [[ "${INSTALL_ZT,,}" == "y" ]]; then
  info "Installing ZeroTier..."
  curl -s https://install.zerotier.com | bash
  systemctl enable --now zerotier-one || true
  ufw allow 9993/udp comment 'ZeroTier'
  info "ZeroTier installed. UDP 9993 allowed in UFW."
  info "Next: create/join a network at https://my.zerotier.com"
  info "Then run: sudo zerotier-cli join <NETWORK_ID>"
fi

# Enable UFW last (so we don't lock ourselves out)
echo
info "Enabling UFW..."
ufw --force enable
ufw status verbose

echo
info "=== Setup complete ==="
info "User: $USERNAME"
info "SSH: ssh ${USERNAME}@$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
info "UFW is active. Fail2Ban is protecting SSH."
info "Also update your AWS Security Group to match the ports you opened."
warn "Password auth is enabled. Keep Security Group + UFW tight, and use a strong password."
info "Done."
