# ubuntu-scripts

Collection of practical Ubuntu / AWS EC2 setup and hardening scripts.

## Scripts

### `ec2-setup.sh`
Interactive setup script for a new AWS EC2 Ubuntu instance.

**What it does:**
- Updates the system
- Creates / configures a user and sets a password
- Enables password-based SSH login (so you don’t need the `.pem` key every time)
- Installs and configures **UFW** (firewall)
- Installs and configures **Fail2Ban** (SSH brute-force protection)
- Optional installs:
  - Apache + PHP
  - Webmin (port 10000)
  - ZeroTier

**Usage** (after first key-based login):

```bash
curl -fsSL https://raw.githubusercontent.com/xnogard/ubuntu-scripts/main/ec2-setup.sh -o setup.sh
bash setup.sh
```

Or clone the repo and run it locally.

**Security notes:**
- Password authentication is less secure than key-only. Use a strong password.
- Restrict your AWS Security Group to your IP when possible.
- The script enables UFW and Fail2Ban automatically.

### `change-ssh-port.sh`
Hardens SSH by changing the default port and locking down the firewall.

**What it does:**
- Changes SSH port from 22 → 22000
- Disables root login
- Configures UFW (deny incoming by default, allow the new SSH port)
- Removes the old port 22 rule

**Usage:**

```bash
curl -fsSL https://raw.githubusercontent.com/xnogard/ubuntu-scripts/main/change-ssh-port.sh -o change-ssh-port.sh
bash change-ssh-port.sh
```

After running, connect with:

```bash
ssh -p 22000 username@your-server
```

Also update your AWS Security Group to allow TCP 22000 and remove 22 if desired.

## Requirements

- Ubuntu 22.04 / 24.04 (Debian-based) recommended
- Root or sudo access
- For `ec2-setup.sh`: run after the initial key-based SSH login

## License

See [LICENSE](LICENSE).
