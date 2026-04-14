# bootstrap-secure-linux

**Secure your fresh Ubuntu/Debian server in just 60 seconds!**

Run this lightning-fast first-minute bootstrap script right after provisioning—it instantly creates a non-root sudo user, locks down SSH, fires up a deny-by-default firewall, adds brute-force protection, and enables automatic security updates. Hit the ground running with a rock-solid secure baseline—before you install apps or expose services.

## What this script is for

- **New server baseline**: you just provisioned a VPS/cloud instance and need sane defaults fast.
- **Reduce common compromise paths**: disable risky SSH settings (root login, passwords), add a firewall, and install basic security tooling.
- **Make results reproducible**: the script applies the same baseline each time and captures a full log.

## Supported systems

- **Debian/Ubuntu-based** systems with `apt` (the script uses `apt`, `ufw`, `systemctl`, `timedatectl`).

## How to run

### Run remotely (recommended)

Run it directly on the server as root:

```bash
curl -fsSL https://raw.githubusercontent.com/mrmierzejewski/bootstrap-secure-linux/refs/heads/master/boostrap-secure-linux.sh | sudo bash
```

### Download and run locally (optional)

If you prefer to inspect the script first (recommended for production), download it, review it, then run:

```bash
curl -fsSLO https://raw.githubusercontent.com/mrmierzejewski/bootstrap-secure-linux/refs/heads/master/boostrap-secure-linux.sh
chmod +x bootstrap-secure-linux.sh
sudo ./bootstrap-secure-linux.sh
```

It will prompt you for:

- a new sudo username + password
- a path to an SSH public key (default: `~/.ssh/id_rsa.pub`)
- optional extra UFW ports (e.g. `80,443`)
- locale and timezone

### Logs

The script writes detailed output to a log file created in **your current working directory**:

- **Filename format**: `bootstrap-secure-linux-YYYYMMDDHHMMSS.log`
- **Example**: `bootstrap-secure-linux-20260414153012.log`

## Options

### `-h`, `--help`

Shows built-in help/usage and exits.

## What it changes (and why)

Below is the full set of changes the script applies, with rationale for each one.

### User & access management

- **Create a non-root user and add to `sudo`**
  - **Why**: day-to-day admin work should not happen as root. Using `sudo` adds friction and logging, and reduces damage from mistakes.
- **Install an SSH public key for that user**
  - **Why**: key-based authentication is far more resistant to brute-force attacks than passwords, and avoids password reuse/leaks.

### SSH hardening (`/etc/ssh/sshd_config`)

The script modifies SSH settings and restarts the SSH service:

- **Disable root login** (`PermitRootLogin no`)
  - **Why**: attackers target `root` first. Removing direct root access forces use of a named account and `sudo`, improving accountability and reducing risk.
- **Disable password authentication** (`PasswordAuthentication no`)
  - **Why**: eliminates online password brute forcing. You authenticate via SSH keys only.
- **Disable X11 forwarding** (`X11Forwarding no`)
  - **Why**: reduces attack surface and prevents forwarding-related abuse on servers that don’t need GUI forwarding.
- **Limit authentication attempts** (`MaxAuthTries 3`)
  - **Why**: slows down brute-force attempts and reduces log noise.
- **Allow only your new user** (`AllowUsers <username>`)
  - **Why**: even if additional accounts exist, SSH login is restricted to the explicit admin user, reducing lateral entry points.
- **Back up original SSH config**
  - **Why**: safer recovery if you need to roll back changes.

### Firewall (UFW)

- **Default deny inbound, allow outbound**
  - **Why**: most servers should only expose a small set of services. Deny-by-default prevents accidental exposure.
- **Allow SSH**
  - **Why**: you need remote access to administer the server.
- **Optionally allow additional ports**
  - **Why**: lets you open only what you need (e.g. HTTP/HTTPS).

#### Important note about Docker

Docker can manipulate `iptables` directly and may bypass UFW rules depending on configuration. If you plan to run Docker, strongly consider using a cloud-provider firewall (Security Groups / VPC firewall / edge firewall) as the authoritative perimeter control.

### Kernel network hardening (sysctl)

The script writes `/etc/sysctl.d/99-security.conf` and applies it via `sysctl --system`.

Settings include:

- **Reverse path filtering** (`rp_filter`)
  - **Why**: helps mitigate IP spoofing on multi-homed systems and some misrouting scenarios.
- **Ignore ICMP broadcasts**
  - **Why**: reduces susceptibility to certain amplification/SMURF-style legacy attack patterns.
- **Disable source routing**
  - **Why**: source-routed packets are rarely needed and are a known risk.
- **Disable ICMP redirects**
  - **Why**: prevents route-manipulation attacks and misconfig-induced rerouting.
- **Enable SYN cookies**
  - **Why**: improves resilience against SYN flood attacks.
- **Tune SYN backlog and retry counts**
  - **Why**: small resilience improvements under abusive or high-latency conditions.

### Secure shared memory (`/dev/shm`)

- **Mount `/dev/shm` with `noexec,nosuid,nodev`**
  - **Why**: reduces the risk of executing malicious payloads from shared memory and limits privilege escalation vectors that rely on `suid`/device nodes.
  - The script appends an entry to `/etc/fstab` (if missing) and remounts.

### Intrusion prevention: Fail2ban

- **Install and configure Fail2ban**
  - **Why**: automatically bans IPs that repeatedly fail authentication, reducing brute-force noise and load.
- **Enable an `sshd` jail**
  - **Why**: focuses on the most common exposed service on new servers: SSH.

### Auditing: auditd

- **Install `auditd`**
  - **Why**: provides low-level security auditing, useful for forensics and monitoring critical system events.

### Automatic security updates: unattended-upgrades

- **Enable unattended security upgrades**
  - **Why**: reduces the window of exposure for known vulnerabilities by automatically applying security updates.
  - This is especially important for servers that won’t be actively maintained daily.

### Locale and timezone

- **Set locale and timezone**
  - **Why**: consistent system locale/timezone improves log readability, correlating events, and operational correctness (cron, timestamps).

### Reboot prompt

- The script offers to reboot at the end.
  - **Why**: some security updates and kernel-level changes may require a restart to fully apply.

## Operational safety notes

- **Run from a safe environment**: execute from a machine/network where you can maintain SSH access.
- **Keep a second terminal open**: after hardening SSH, test logging in as the new user before closing your root session.
- **Be careful with SSH changes**: if you mis-specify the SSH key path or lock down SSH incorrectly, you can lock yourself out. The script tries to be safe, but always validate access.

## License

Released under the MIT License
