#!/bin/bash

# Exit immediately on errors, undefined variables, or pipe failures
set -euo pipefail

# --- UI & Styling Variables ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log file in the directory the script is run from
default_script_name="bootstrap-secure-linux"
run_timestamp="$(date +"%Y%m%d%H%M%S")"
LOG_FILE="$(pwd -P)/${default_script_name}-${run_timestamp}.log"

# --- Helper Functions ---
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[ OK ]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

show_help() {
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${CYAN}      Secure Server Provisioning Script V2       ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo -e "Usage: sudo ./$(basename "$0") [OPTIONS]\n"
    echo -e "${YELLOW}Description:${NC}"
    echo "  This script fully provisions and hardens a fresh Debian/Ubuntu server."
    echo "  It establishes a secure baseline by configuring a new sudo user, hardening"
    echo "  network services, and setting up automated defenses.\n"
    echo -e "${YELLOW}Features Applied:${NC}"
    echo -e "  ${GREEN}1. User & Access Management${NC}"
    echo "     - Creates a new standard user with sudo privileges."
    echo "     - Ingests an SSH public key for secure login."
    echo -e "  ${GREEN}2. SSH Hardening (/etc/ssh/sshd_config)${NC}"
    echo "     - Disables Root login."
    echo "     - Disables Password authentication."
    echo "     - Disables X11 Forwarding."
    echo "     - Limits MaxAuthTries to 3."
    echo "     - Restricts SSH access ONLY to the newly created user (AllowUsers)."
    echo -e "  ${GREEN}3. Network & Firewall${NC}"
    echo "     - Configures UFW (Uncomplicated Firewall) to deny inbound, allow outbound."
    echo "       *NOTE: UFW is bypassed by Docker. Use an external firewall if using Docker."
    echo "     - Allows SSH and optional user-defined ports (e.g., 80, 443)."
    echo "     - Applies Kernel sysctl rules to prevent IP spoofing, SYN floods, and ICMP redirects."
    echo -e "  ${GREEN}4. Intrusion Prevention & Auditing${NC}"
    echo "     - Installs and configures Fail2ban with a custom SSH jail."
    echo "     - Installs Auditd for system-level security auditing."
    echo -e "  ${GREEN}5. System Hardening & Maintenance${NC}"
    echo "     - Mounts /dev/shm with noexec, nosuid, and nodev flags."
    echo "     - Installs and enables unattended-upgrades for automatic security patches."
    echo "     - Configures system Locale and Timezone."
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -h, --help    Show this help message and exit\n"
}

# Fancy Braille Spinner for long-running background tasks
run_with_spinner() {
    local msg="$1"
    shift
    # Start the command in the background, redirecting output to the log
    "$@" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    local delay=0.05
    # Braille characters for a smooth circular spinner
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    printf "${BLUE}[ .. ]${NC} ${msg}..."

    # While the process is running, spin
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r${BLUE}[ %c ]${NC} ${msg}..." "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done

    # Wait for the process to actually finish and grab its exit code
    wait $pid
    local status=$?

    if [ $status -eq 0 ]; then
        printf "\r${GREEN}[ OK ]${NC} ${msg}... Done!\n"
    else
        printf "\r${RED}[FAIL]${NC} ${msg}... Failed!\n"
        echo -e "       ${RED}-> Check $LOG_FILE for details.${NC}"
        exit $status
    fi
}

# --- Argument Parsing ---
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
esac

# ==========================================
# Script Start
# ==========================================

# 1. Check if the script is run as root BEFORE touching root-owned directories
if [ "$(id -u)" != "0" ]; then
   error "This script must be run as root. Try: sudo $0"
fi

# 2. Now it is safe to clear/create the log file
> "$LOG_FILE"

clear
echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}      Secure Server Provisioning Script V2       ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo ""

# --- Interactive Prompts (Done upfront so the user can walk away) ---
info "Gathering configuration details..."

if ! [ -t 0 ] && ! [ -r /dev/tty ]; then
    error "No interactive TTY available. Run from an interactive SSH session, or download the script and run it locally."
fi

declare username=""
declare password=""
declare password_confirm=""
declare ssh_key_path=""
declare other_ports=""
declare locale=""
declare timezone=""

read -p "Enter username for the new sudo user: " username < /dev/tty || error "Failed to read username (no TTY?)."
read -s -p "Enter password for ${username}: " password < /dev/tty || error "Failed to read password (no TTY?)."
echo > /dev/tty
read -s -p "Confirm password: " password_confirm < /dev/tty || error "Failed to read password confirmation (no TTY?)."
echo > /dev/tty
if [ "$password" != "$password_confirm" ]; then
    error "Passwords do not match."
fi

read -p "Enter path to SSH public key [~/.ssh/id_rsa.pub]: " ssh_key_path < /dev/tty || error "Failed to read SSH key path (no TTY?)."
ssh_key_path=${ssh_key_path:-~/.ssh/id_rsa.pub}
if [ ! -f "$ssh_key_path" ]; then
    error "SSH public key file not found at $ssh_key_path"
fi

echo ""
warn "Docker & Firewall Compatibility:"
echo -e "       If you plan to run Docker on this server, UFW is often insufficient."
echo -e "       Docker directly manipulates iptables and bypasses UFW, which can"
echo -e "       unintentionally expose your container ports to the public internet."
echo -e "       ${GREEN}Recommendation:${NC} Use an external cloud-provider firewall (e.g.,"
echo -e "       AWS Security Groups, DigitalOcean Firewalls) if using Docker."
echo ""
read -p "Do you want to allow any other UFW ports? (e.g., 80,443) [none]: " other_ports < /dev/tty || error "Failed to read additional ports (no TTY?)."

read -p "Enter locale [en_US.UTF-8]: " locale < /dev/tty || error "Failed to read locale (no TTY?)."
locale=${locale:-en_US.UTF-8}

read -p "Enter timezone [UTC]: " timezone < /dev/tty || error "Failed to read timezone (no TTY?)."
timezone=${timezone:-UTC}

echo ""
info "Starting automated configuration. Detailed logs saved to $LOG_FILE"
echo ""

# --- Automated Setup Steps ---

run_with_spinner "Updating system packages" apt update
run_with_spinner "Upgrading system packages" env DEBIAN_FRONTEND=noninteractive apt upgrade -y
run_with_spinner "Installing security tools (UFW, Fail2ban, Auditd)" env DEBIAN_FRONTEND=noninteractive apt install -y ufw fail2ban unattended-upgrades auditd audispd-plugins

# Create the new user
info "Setting up user: ${YELLOW}$username${NC}"
useradd -m -s /bin/bash "$username" || true  # Ignore if user exists
echo "$username:${password:?Password not set}" | chpasswd
usermod -aG sudo "$username"
success "User created and granted sudo privileges"

# Set up SSH key
mkdir -p /home/"$username"/.ssh
cp "$ssh_key_path" /home/"$username"/.ssh/authorized_keys
chown -R "$username":"$username" /home/"$username"/.ssh
chmod 700 /home/"$username"/.ssh
chmod 600 /home/"$username"/.ssh/authorized_keys
success "SSH keys configured for $username"

# Configure SSH daemon
run_with_spinner "Hardening SSH configuration" bash -c "
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i 's/#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#\?X11Forwarding .*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/#\?MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
if ! grep -q '^AllowUsers' /etc/ssh/sshd_config; then
    echo 'AllowUsers $username' >> /etc/ssh/sshd_config
else
    sed -i 's/^AllowUsers.*/AllowUsers $username/' /etc/ssh/sshd_config
fi
systemctl restart ssh
"

# Secure Shared Memory (/dev/shm)
run_with_spinner "Securing shared memory (/dev/shm)" bash -c "
if ! grep -q '/dev/shm' /etc/fstab; then
    echo 'tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0' >> /etc/fstab
    mount -o remount /dev/shm || true
fi
"

# Kernel Network Hardening (sysctl)
run_with_spinner "Applying kernel network security settings" bash -c "
cat <<EOF > /etc/sysctl.d/99-security.conf
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
EOF
sysctl --system
"

# Configure UFW firewall
run_with_spinner "Configuring UFW Firewall" bash -c "
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
if [ -n '$other_ports' ]; then
    for port in $other_ports; do
        ufw allow \"\$port\"
    done
fi
ufw --force enable
"

# Configure Fail2ban
run_with_spinner "Configuring Fail2ban" bash -c "
cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
systemctl enable fail2ban
systemctl restart fail2ban
"

# Configure Unattended Upgrades
run_with_spinner "Enabling automatic security updates" bash -c "
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
"

# Locale and Timezone
run_with_spinner "Setting Locale ($locale) and Timezone ($timezone)" bash -c "
locale-gen '$locale'
update-locale LANG='$locale'
timedatectl set-timezone '$timezone'
"

echo ""
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}             Setup Completed Successfully        ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo ""
warn "CRITICAL STEP: Please test logging in with your new user:"
echo -e "       ${YELLOW}ssh $username@<your_server_ip>${NC}"
echo -e "       Do this from ANOTHER terminal before closing this one."
echo ""

read -p "Do you want to reboot the server now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Rebooting server..."
    reboot
else
    info "Skipping reboot. You are good to go!"
fi
