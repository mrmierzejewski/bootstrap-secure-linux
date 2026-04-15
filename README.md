# bootstrap-secure-linux

**Secure your fresh Ubuntu or Debian server in about a minute.**

Secure your Linux server in 60 seconds with a single command! `bootstrap-secure-linux` transforms your fresh install into a hardened, production-ready machine-automatically. It creates a dedicated admin user, locks down SSH to key-based logins, blocks everything at the firewall except what you explicitly allow, and sets up automatic security updates. Eliminate common threats like password attacks, accidental open ports, and missed patches—instantly and effortlessly.

Works out of the box for **Debian and Ubuntu** systems that use `apt`, `ufw`, and `systemd` (`systemctl`, `timedatectl`). Every run is consistent and logs all actions to your local directory for full transparency.

## How to run it

The usual approach is to pipe the script straight from the network into the shell on the server (as root):

```bash
curl -fsSL https://raw.githubusercontent.com/mrmierzejewski/bootstrap-secure-linux/refs/heads/main/bootstrap-secure-linux.sh | sudo bash
```

If you would rather read the script before you execute it—which is a good idea in production—download it, inspect it, make it executable, and run it locally:

```bash
curl -fsSLO https://raw.githubusercontent.com/mrmierzejewski/bootstrap-secure-linux/refs/heads/main/bootstrap-secure-linux.sh
chmod +x bootstrap-secure-linux.sh
sudo ./bootstrap-secure-linux.sh
```

The script is interactive. It will ask for a new sudo username and password, the path to an SSH public key (defaulting to `~/.ssh/id_rsa.pub` if you press Enter), any **extra** firewall ports beyond the defaults (see below), plus locale and timezone. It writes a full log next to where you ran it, named like `bootstrap-secure-linux-YYYYMMDDHHMMSS.log`, so you can review what happened without scrolling the terminal.

Pass `-h` or `--help` to print usage and exit without changing the system.

## What the script actually does

**Users and SSH.** It creates a normal user with sudo and installs your public key so you can log in without passwords over SSH. Day-to-day work should not use the root account directly; `sudo` adds a small barrier and better traceability. Keys beat passwords for resistance to brute-force and reuse.

**SSH daemon.** It tightens `/etc/ssh/sshd_config`: no direct root login, no password authentication (keys only), X11 forwarding off, a low `MaxAuthTries`, and `AllowUsers` limited to the user you just created. Attackers probe `root` and passwords first; this configuration pushes you toward named accounts and keys. The original config is copied aside before changes, and the SSH service is restarted.

**Firewall.** UFW is reset to **deny incoming by default** and **allow outgoing**. By default it allows **SSH (port 22)**, **HTTP (80)**, and **HTTPS (443)**; the prompt only asks if you need **additional** ports beyond that. That keeps accidental exposure small while still covering typical web stacks. If you run Docker, remember that Docker can manipulate `iptables` in ways that bypass UFW, so a cloud-provider firewall (security groups, VPC rules, or similar) is still the right place for your real perimeter when containers are in play.

**Kernel tuning.** A small `sysctl` profile is written under `/etc/sysctl.d/` and applied—reverse-path filtering, turning off risky IP behaviors, SYN cookies, and a few TCP tuning knobs—to shave risk from spoofing, floods, and noisy network abuse.

**Shared memory.** If needed, `/dev/shm` is mounted with `noexec`, `nosuid`, and `nodev` via `fstab` and remounted, which makes it harder to abuse shared memory for execution or privilege tricks.

**Fail2ban and auditd.** Fail2ban gets an SSH jail so repeated failed logins get blocked automatically. `auditd` is installed for host-level auditing when you need to dig into what happened after the fact.

**Updates and housekeeping.** Unattended security upgrades are enabled so critical patches do not wait for a manual `apt` day. Locale and timezone are set so logs and cron line up with how you expect to read them. At the end you can reboot so anything that needs a full restart (kernel or deep libraries) is not left half-applied.

## Using it safely

Run it from a session where you can afford to lose this shell only after you have confirmed a second way in - ideally **another terminal** where you `ssh` as the new user before you close the root session. Wrong SSH key paths or typos are how people lock themselves out; the script is conservative, but verification is still on you.

## License

Released under the MIT License.
