#!/usr/bin/env bash
set -euo pipefail

# Ubuntu Server bootstrap script
# Installs useful base packages, OpenSSH, UFW, Tailscale,
# unattended upgrades, weekly apt update job, and weekly reboot.

if [[ $EUID -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

log() {
  echo ""
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

require_ubuntu() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      echo "Warning: this script is designed for Ubuntu Server. Detected: ${PRETTY_NAME:-unknown}"
      read -rp "Continue anyway? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] || exit 1
    fi
  fi
}

set_timezone() {
  log "Setting timezone to Europe/London"
  $SUDO timedatectl set-timezone Europe/London
  timedatectl | grep "Time zone" || true
}

install_base_packages() {
  log "Updating apt and installing base packages"
  $SUDO dpkg --configure -a
  $SUDO apt update
  $SUDO apt upgrade -y
  $SUDO apt install -y \
    curl \
    git \
    htop \
    nano \
    ca-certificates \
    gnupg \
    lsb-release \
    openssh-server \
    ufw \
    unattended-upgrades \
    apt-listchanges \
    smartmontools
}

setup_ssh() {
  log "Enabling SSH"
  $SUDO systemctl enable --now ssh
  $SUDO systemctl status ssh --no-pager || true
}

setup_ufw() {
  log "Configuring UFW firewall"
  $SUDO ufw allow 22/tcp comment 'SSH'
  $SUDO ufw allow OpenSSH || true
  $SUDO ufw --force enable
  $SUDO ufw status verbose
}

install_tailscale() {
  log "Installing Tailscale"
  if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
  else
    echo "Tailscale already installed."
  fi

  $SUDO systemctl enable --now tailscaled

  echo ""
  echo "Tailscale installed. To connect this server to your Tailnet, run:"
  echo "  sudo tailscale up"
  echo ""
}

setup_unattended_upgrades() {
  log "Configuring unattended upgrades"
  echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | $SUDO debconf-set-selections
  $SUDO dpkg-reconfigure -f noninteractive unattended-upgrades
  $SUDO systemctl enable --now unattended-upgrades
}

create_weekly_update_script() {
  log "Creating weekly update script"
  $SUDO tee /usr/local/bin/server-update.sh >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/server-update.log"

{
  echo "=================================================="
  echo "Server update started: $(date)"
  echo "=================================================="

  dpkg --configure -a
  apt update
  apt upgrade -y
  apt autoremove -y
  apt autoclean
  apt clean

  echo "=================================================="
  if [[ -f /var/run/reboot-required ]]; then
    echo "Reboot required. Weekly reboot timer will handle this."
  else
    echo "No reboot currently required."
  fi
  echo "Server update finished: $(date)"
  echo "=================================================="
} | tee -a "$LOG_FILE"
SCRIPT

  $SUDO chmod +x /usr/local/bin/server-update.sh
}

setup_cron_update() {
  log "Adding Sunday 2AM apt update cron job"
  CRON_FILE="/etc/cron.d/server-weekly-update"
  $SUDO tee "$CRON_FILE" >/dev/null <<'CRON'
# Run server updates every Sunday at 2AM local time
0 2 * * 0 root /usr/local/bin/server-update.sh
CRON
  $SUDO chmod 644 "$CRON_FILE"
}

setup_weekly_reboot_timer() {
  log "Creating Sunday 3AM reboot systemd timer"

  $SUDO tee /etc/systemd/system/weekly-reboot.service >/dev/null <<'SERVICE'
[Unit]
Description=Weekly Sunday Reboot

[Service]
Type=oneshot
ExecStart=/usr/sbin/reboot
SERVICE

  $SUDO tee /etc/systemd/system/weekly-reboot.timer >/dev/null <<'TIMER'
[Unit]
Description=Weekly Sunday 3AM Reboot

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER

  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now weekly-reboot.timer
}

enable_smartd() {
  log "Enabling SMART disk monitoring"
  $SUDO systemctl enable --now smartd || true
}

cleanup() {
  log "Final cleanup"
  $SUDO apt autoremove -y
  $SUDO apt autoclean
  $SUDO apt clean
}

show_summary() {
  log "Setup complete"
  echo "Hostname: $(hostname)"
  echo "LAN IP(s): $(hostname -I || true)"
  echo "Timezone: $(timedatectl | grep 'Time zone' | sed 's/^ *//')"
  echo ""
  echo "Next steps:"
  echo "1. Run: sudo tailscale up"
  echo "2. SSH locally: ssh <username>@<LAN-IP>"
  echo "3. SSH via Tailscale after login: ssh <username>@<TAILSCALE-IP>"
  echo "4. Check timers: systemctl list-timers | grep -E 'weekly-reboot|apt|server'"
  echo ""
  echo "Weekly schedule:"
  echo "- Sunday 02:00: apt updates"
  echo "- Sunday 03:00: reboot"
}

main() {
  require_ubuntu
  set_timezone
  install_base_packages
  setup_ssh
  setup_ufw
  install_tailscale
  setup_unattended_upgrades
  create_weekly_update_script
  setup_cron_update
  setup_weekly_reboot_timer
  enable_smartd
  cleanup
  show_summary
}

main "$@"
