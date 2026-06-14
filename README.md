# Ubuntu Server Bootstrap

Simple bootstrap script for a fresh Ubuntu Server install.

It sets up the basics for a home server, including SSH, firewall rules, Tailscale, automatic updates, and a weekly reboot.

## What it does

- Updates Ubuntu packages
- Installs useful base packages
- Installs and enables OpenSSH Server
- Installs and enables UFW
- Opens port `22` for SSH
- Installs Tailscale
- Sets timezone to `Europe/London`
- Installs unattended upgrades
- Creates a weekly update script
- Runs updates every Sunday at `02:00`
- Reboots every Sunday at `03:00`
- Installs and enables SMART disk monitoring

## What it does not do

- Does not change SSH password/key settings
- Does not expose services to the internet

## Quick install

Run this on a fresh Ubuntu Server:

```bash
curl -fsSL https://raw.githubusercontent.com/AmirIqbal1/ubuntu-server-bootstrap/refs/heads/main/server-bootstrap.sh -o server-bootstrap.sh
chmod +x server-bootstrap.sh
./server-bootstrap.sh
```

## After install

Connect the server to Tailscale:

```bash
sudo tailscale up
```

Check your server IPs:

```bash
hostname -I
tailscale ip -4
```

SSH using LAN:

```bash
ssh yourusername@192.168.1.xxx
```

SSH using Tailscale:

```bash
ssh yourusername@100.xxx.xxx.xxx
```

## Check automation

Check the reboot timer:

```bash
systemctl list-timers | grep weekly-reboot
```

Check unattended upgrades:

```bash
systemctl status unattended-upgrades
```

Check weekly update cron:

```bash
cat /etc/cron.d/server-weekly-update
```

Manual update run:

```bash
sudo /usr/local/bin/server-update.sh
```

Update logs:

```bash
cat /var/log/server-update.log
```

## Firewall

Show firewall status:

```bash
sudo ufw status verbose
```

Expected SSH rule:

```text
22/tcp ALLOW Anywhere
```
