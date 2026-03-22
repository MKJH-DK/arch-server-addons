#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Security Audit Script — comprehensive server security tests
# Installs third-party tools, runs all checks, logs results,
# then removes all installed tools (no trace).
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -uo pipefail

# ── Colors ──────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Counters ────────────────────────────────────────────────
PASSED=0
FAILED=0
WARNINGS=0
TOTAL=0

# ── Log file ────────────────────────────────────────────────
LOG_DIR="/var/log/security-audit"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/audit-$TIMESTAMP.log"
JSON_FILE="$LOG_DIR/audit-$TIMESTAMP.json"

# Track installed packages for cleanup
INSTALLED_PACKAGES=()

# ── Output helpers ──────────────────────────────────────────
log() {
    echo "$1" >> "$LOG_FILE"
}

check_pass() {
    ((PASSED++)); ((TOTAL++))
    echo -e "  ${GREEN}✓${NC} $1"
    log "PASS: $1"
}

check_fail() {
    ((FAILED++)); ((TOTAL++))
    echo -e "  ${RED}✗${NC} $1"
    log "FAIL: $1"
}

check_warn() {
    ((WARNINGS++)); ((TOTAL++))
    echo -e "  ${YELLOW}!${NC} $1"
    log "WARN: $1"
}

section() {
    echo ""
    echo -e "${BLUE}[$1]${NC}"
    log ""
    log "[$1]"
}

separator() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Package management (install + track for cleanup) ────────
pkg_install() {
    for pkg in "$@"; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            pacman -S --noconfirm --needed "$pkg" &>/dev/null
            if pacman -Q "$pkg" &>/dev/null; then
                INSTALLED_PACKAGES+=("$pkg")
                log "INSTALLED: $pkg (will be removed)"
            fi
        fi
    done
}

pkg_cleanup() {
    if [[ ${#INSTALLED_PACKAGES[@]} -eq 0 ]]; then
        return
    fi
    echo ""
    echo -e "${BLUE}[CLEANUP]${NC}"
    for pkg in "${INSTALLED_PACKAGES[@]}"; do
        if pacman -Q "$pkg" &>/dev/null; then
            pacman -Rns --noconfirm "$pkg" &>/dev/null
            if ! pacman -Q "$pkg" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Removed: $pkg"
                log "REMOVED: $pkg"
            else
                echo -e "  ${YELLOW}!${NC} Could not remove: $pkg (dependency?)"
                log "WARN: Could not remove $pkg"
            fi
        fi
    done
    # Clean pacman cache for installed packages
    pacman -Sc --noconfirm &>/dev/null
}

# ── Root check ──────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}Security Audit — $(date '+%Y-%m-%d %H:%M')${NC}"
separator
log "Security Audit — $(date '+%Y-%m-%d %H:%M:%S')"
log "Hostname: $(hostname)"
log "Kernel: $(uname -r)"

# ── Install audit tools ────────────────────────────────────
echo -e "${BLUE}[SETUP]${NC}"
echo -e "  Installing audit tools..."
pkg_install lynis nmap net-tools lsof

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. KERNEL HARDENING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "KERNEL HARDENING"

# ASLR
aslr=$(sysctl -n kernel.randomize_va_space 2>/dev/null)
[[ "$aslr" == "2" ]] && check_pass "ASLR fully enabled (randomize_va_space=2)" || check_fail "ASLR not fully enabled (got $aslr, want 2)"

# Kernel pointer restriction
kptr=$(sysctl -n kernel.kptr_restrict 2>/dev/null)
[[ "$kptr" -ge 1 ]] && check_pass "Kernel pointers restricted (kptr_restrict=$kptr)" || check_fail "Kernel pointers exposed (kptr_restrict=$kptr)"

# dmesg restriction
dmesg_r=$(sysctl -n kernel.dmesg_restrict 2>/dev/null)
[[ "$dmesg_r" == "1" ]] && check_pass "dmesg restricted to root" || check_fail "dmesg accessible to all users"

# Symlink/hardlink protection
sym=$(sysctl -n fs.protected_symlinks 2>/dev/null)
hard=$(sysctl -n fs.protected_hardlinks 2>/dev/null)
[[ "$sym" == "1" && "$hard" == "1" ]] && check_pass "Symlink/hardlink protection enabled" || check_fail "Symlink/hardlink protection missing (sym=$sym hard=$hard)"

# SYN cookies
syncookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)
[[ "$syncookies" == "1" ]] && check_pass "SYN cookies enabled" || check_fail "SYN cookies disabled"

# IP forwarding (should be off unless router)
ipfwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
[[ "$ipfwd" == "0" ]] && check_pass "IP forwarding disabled" || check_warn "IP forwarding enabled (ok if using containers/tunnel)"

# Source routing
src_route=$(sysctl -n net.ipv4.conf.all.accept_source_route 2>/dev/null)
[[ "$src_route" == "0" ]] && check_pass "Source routing disabled" || check_fail "Source routing accepted"

# Reverse path filtering
rpf=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null)
[[ "$rpf" -ge 1 ]] && check_pass "Reverse path filtering enabled (rp_filter=$rpf)" || check_fail "Reverse path filtering disabled"

# ICMP redirects
icmp_r=$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null)
[[ "$icmp_r" == "0" ]] && check_pass "ICMP redirects rejected" || check_fail "ICMP redirects accepted"

# Core dumps
core=$(sysctl -n fs.suid_dumpable 2>/dev/null)
[[ "$core" == "0" ]] && check_pass "SUID core dumps disabled" || check_warn "SUID core dumps enabled ($core)"

# Kernel module loading
mod_disabled=$(sysctl -n kernel.modules_disabled 2>/dev/null)
[[ "$mod_disabled" == "1" ]] && check_pass "Kernel module loading disabled" || check_warn "Kernel module loading still allowed (ok during setup)"

# Blacklisted modules
blacklisted=0
for mod in usb-storage firewire-core thunderbolt; do
    if grep -rq "blacklist $mod\|install $mod /bin/false\|install $mod /bin/true" /etc/modprobe.d/ 2>/dev/null; then
        ((blacklisted++))
    fi
done
[[ $blacklisted -ge 2 ]] && check_pass "Dangerous kernel modules blacklisted ($blacklisted/3)" || check_warn "Only $blacklisted/3 dangerous modules blacklisted"

# Secure Boot
sb_var=$(find /sys/firmware/efi/efivars/ -name 'SecureBoot-*' 2>/dev/null | head -1)
if [ -n "$sb_var" ] && [ "$(od -An -t u1 -j4 -N1 "$sb_var" 2>/dev/null | tr -d ' ')" = "1" ]; then
    check_pass "Secure Boot enabled"
elif command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    check_pass "Secure Boot enabled"
else
    check_warn "Secure Boot not detected"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. SSH HARDENING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "SSH HARDENING"

sshd_config=$(sshd -T 2>/dev/null)

ssh_check() {
    local key="$1" want="$2" label="$3"
    local got
    got=$(echo "$sshd_config" | grep -i "^$key " | awk '{print $2}')
    if [[ "${got,,}" == "${want,,}" ]]; then
        check_pass "$label ($key=$got)"
    else
        check_fail "$label ($key=$got, want $want)"
    fi
}

ssh_check "permitrootlogin" "no" "Root login disabled"
ssh_check "passwordauthentication" "no" "Password auth disabled"
ssh_check "permitemptypasswords" "no" "Empty passwords rejected"
ssh_check "x11forwarding" "no" "X11 forwarding disabled"
ssh_check "maxauthtries" "3" "Max auth tries limited"
ssh_check "pubkeyauthentication" "yes" "Public key auth enabled"

# SSH protocol version (only v2)
if ! echo "$sshd_config" | grep -qi "protocol 1"; then
    check_pass "SSH protocol v1 disabled"
else
    check_fail "SSH protocol v1 still allowed"
fi

# Authorized keys file permissions
auth_files=$(find /home -name "authorized_keys" -type f 2>/dev/null)
bad_perms=0
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    perms=$(stat -c %a "$f" 2>/dev/null)
    if [[ "$perms" != "600" && "$perms" != "400" ]]; then
        ((bad_perms++))
    fi
done <<< "$auth_files"
[[ $bad_perms -eq 0 ]] && check_pass "authorized_keys file permissions ok" || check_fail "$bad_perms authorized_keys files have loose permissions"

# Recent failed SSH logins (24h)
failed_ssh=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -c "Failed\|Invalid" || echo 0)
[[ $failed_ssh -lt 10 ]] && check_pass "Failed SSH logins last 24h: $failed_ssh" || check_warn "High failed SSH attempts: $failed_ssh in 24h"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. FIREWALL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "FIREWALL"

if systemctl is-active nftables &>/dev/null; then
    check_pass "nftables service active"
else
    check_fail "nftables service not running"
fi

rule_count=$(nft list ruleset 2>/dev/null | wc -l)
[[ $rule_count -gt 5 ]] && check_pass "nftables rules loaded ($rule_count lines)" || check_fail "nftables has no/minimal rules ($rule_count lines)"

# Default deny policy
if nft list ruleset 2>/dev/null | grep -q "policy drop\|policy reject"; then
    check_pass "Default deny policy detected"
else
    check_warn "No default deny policy found in nftables"
fi

# Open ports scan
section "OPEN PORTS"
open_ports=$(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | sed 's/.*://' | sort -un)
expected_ports="22 80 443 8384 9100"
for port in $open_ports; do
    if echo "$expected_ports" | grep -qw "$port"; then
        check_pass "Port $port open (expected)"
    elif [[ $port -gt 1024 ]]; then
        svc=$(ss -tlnp 2>/dev/null | grep ":$port " | sed 's/.*users:(("//' | sed 's/".*//')
        check_warn "Port $port open (service: ${svc:-unknown})"
    else
        svc=$(ss -tlnp 2>/dev/null | grep ":$port " | sed 's/.*users:(("//' | sed 's/".*//')
        check_fail "Unexpected privileged port $port open (service: ${svc:-unknown})"
    fi
done
log "Open ports: $open_ports"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. USER & ACCESS CONTROL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "USER & ACCESS CONTROL"

# Users with UID 0
uid0_count=$(awk -F: '$3 == 0 {print $1}' /etc/passwd | wc -l)
[[ $uid0_count -eq 1 ]] && check_pass "Only root has UID 0" || check_fail "$uid0_count users have UID 0"

# Users with empty passwords
empty_pw=$(awk -F: '($2 == "" || $2 == "!") && $1 != "root" {print $1}' /etc/shadow 2>/dev/null | wc -l)
[[ $empty_pw -eq 0 ]] && check_pass "No users with empty passwords" || check_fail "$empty_pw users with empty/disabled passwords"

# Password hashing algorithm
hash_algo=$(awk -F'$' '/^\$/ {print $2; exit}' /etc/shadow 2>/dev/null)
case "$hash_algo" in
    6) check_pass "Password hashing: SHA-512" ;;
    y|yescrypt) check_pass "Password hashing: yescrypt" ;;
    2b|2a) check_pass "Password hashing: bcrypt" ;;
    *) check_warn "Password hashing algorithm: $hash_algo" ;;
esac

# Sudoers NOPASSWD check
if grep -rq "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
    check_warn "NOPASSWD found in sudoers config"
else
    check_pass "No NOPASSWD entries in sudoers"
fi

# Home directory permissions
bad_homes=0
for dir in /home/*/; do
    [[ ! -d "$dir" ]] && continue
    perms=$(stat -c %a "$dir" 2>/dev/null)
    if [[ "${perms:2:1}" =~ [rwx1-7] ]]; then
        ((bad_homes++))
        log "FAIL: $dir has world-accessible permissions ($perms)"
    fi
done
[[ $bad_homes -eq 0 ]] && check_pass "Home directories not world-accessible" || check_fail "$bad_homes home dirs are world-accessible"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. FILE SYSTEM SECURITY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "FILE SYSTEM"

# SUID binaries
suid_count=$(find / -perm -4000 -type f 2>/dev/null | wc -l)
[[ $suid_count -lt 20 ]] && check_pass "SUID binaries: $suid_count (reasonable)" || check_warn "SUID binaries: $suid_count (review recommended)"
find / -perm -4000 -type f 2>/dev/null | sort >> "$LOG_FILE"

# SGID binaries
sgid_count=$(find / -perm -2000 -type f 2>/dev/null | wc -l)
[[ $sgid_count -lt 15 ]] && check_pass "SGID binaries: $sgid_count (reasonable)" || check_warn "SGID binaries: $sgid_count (review recommended)"

# World-writable files in system dirs
ww_files=$(find /etc /usr /srv -perm -o+w -type f 2>/dev/null | wc -l)
[[ $ww_files -eq 0 ]] && check_pass "No world-writable files in /etc /usr /srv" || check_fail "$ww_files world-writable files found"
find /etc /usr /srv -perm -o+w -type f 2>/dev/null >> "$LOG_FILE"

# World-writable directories without sticky bit
ww_dirs=$(find / -path /proc -prune -o -path /sys -prune -o -type d \( -perm -0002 -a ! -perm -1000 \) -print 2>/dev/null | wc -l)
[[ $ww_dirs -eq 0 ]] && check_pass "No world-writable dirs without sticky bit" || check_fail "$ww_dirs world-writable dirs without sticky bit"

# Unowned files
unowned=$(find / -path /proc -prune -o -path /sys -prune -o \( -nouser -o -nogroup \) -print 2>/dev/null | head -20 | wc -l)
[[ $unowned -eq 0 ]] && check_pass "No unowned files found" || check_warn "$unowned unowned files found"

# Critical file permissions
for f_check in "/etc/shadow:0:0:640" "/etc/passwd:0:0:644" "/etc/group:0:0:644" "/etc/gshadow:0:0:640" "/etc/ssh/sshd_config:0:0:600"; do
    IFS=: read -r fpath fuid fgid fperms <<< "$f_check"
    if [[ -f "$fpath" ]]; then
        actual_perms=$(stat -c %a "$fpath" 2>/dev/null)
        actual_uid=$(stat -c %u "$fpath" 2>/dev/null)
        if [[ "$actual_perms" -le "$fperms" && "$actual_uid" == "$fuid" ]]; then
            check_pass "$fpath permissions ok ($actual_perms)"
        else
            check_fail "$fpath permissions too loose ($actual_perms, want <=$fperms)"
        fi
    fi
done

# LUKS encryption
if lsblk -f 2>/dev/null | grep -qi luks; then
    check_pass "LUKS disk encryption active"
else
    check_warn "No LUKS encryption detected"
fi

# Btrfs snapshots
if command -v snapper &>/dev/null; then
    snap_count=$(snapper -c root list 2>/dev/null | awk 'NR>2 && NF {c++} END {print c+0}')
    [[ $snap_count -gt 0 ]] && check_pass "Btrfs snapshots: $snap_count available" || check_warn "No Btrfs snapshots found"
fi

# /tmp mount options
tmp_mount=$(findmnt -n /tmp 2>/dev/null)
if echo "$tmp_mount" | grep -q "nosuid"; then
    check_pass "/tmp mounted with nosuid"
else
    check_warn "/tmp missing nosuid mount option"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. SERVICE SECURITY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "SERVICE SECURITY"

# Failed services
failed_svcs=$(systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l)
[[ $failed_svcs -eq 0 ]] && check_pass "No failed systemd services" || check_fail "$failed_svcs failed systemd services"
systemctl --failed --no-legend --no-pager 2>/dev/null >> "$LOG_FILE"

# Systemd security scores for critical services
for svc in caddy sshd crowdsec admin-status-api mcp-server syncthing; do
    if systemctl is-active "$svc" &>/dev/null || systemctl is-enabled "$svc" &>/dev/null; then
        score=$(systemd-analyze security "$svc" 2>/dev/null | tail -1 | grep -oP '[\d.]+(?=/)')
        exposure=$(systemd-analyze security "$svc" 2>/dev/null | tail -1 | grep -oP '(?:OK|EXPOSED|MEDIUM|UNSAFE|SAFE)')
        if [[ "$exposure" == "OK" || "$exposure" == "SAFE" ]]; then
            check_pass "$svc sandboxing: $score ($exposure)"
        elif [[ "$exposure" == "MEDIUM" ]]; then
            check_warn "$svc sandboxing: $score ($exposure)"
        else
            check_warn "$svc sandboxing: ${score:-?} (${exposure:-unknown})"
        fi
        log "$(systemd-analyze security "$svc" 2>/dev/null | tail -1)"
    fi
done

# AppArmor / MAC
if systemctl is-active apparmor &>/dev/null; then
    profiles=$(aa-status 2>/dev/null | grep "profiles are loaded" | grep -oP '\d+' | head -1)
    check_pass "AppArmor active ($profiles profiles loaded)"
else
    check_warn "AppArmor not active"
fi

# Auditd
if systemctl is-active auditd &>/dev/null; then
    rules=$(auditctl -l 2>/dev/null | wc -l)
    check_pass "Auditd active ($rules rules)"
else
    check_fail "Auditd not running"
fi

# AIDE
if command -v aide &>/dev/null; then
    if systemctl is-active aide-check.timer &>/dev/null; then
        check_pass "AIDE integrity monitoring with timer active"
    elif [[ -f /var/lib/aide/aide.db.gz ]]; then
        check_pass "AIDE database exists (timer not active)"
    else
        check_warn "AIDE installed but no database"
    fi
else
    check_warn "AIDE not installed"
fi

# CrowdSec
if systemctl is-active crowdsec &>/dev/null; then
    decisions=$(cscli decisions list -o raw 2>/dev/null | wc -l || echo 0)
    check_pass "CrowdSec IDS active ($((decisions - 1)) active decisions)"
else
    check_warn "CrowdSec not running"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. NETWORK SECURITY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "NETWORK SECURITY"

# DNS over TLS
if grep -q "DNSOverTLS" /etc/systemd/resolved.conf 2>/dev/null; then
    dot_val=$(grep "DNSOverTLS" /etc/systemd/resolved.conf | grep -v "^#" | head -1 | cut -d= -f2)
    [[ "$dot_val" == "yes" || "$dot_val" == "opportunistic" ]] && check_pass "DNS-over-TLS: $dot_val" || check_warn "DNS-over-TLS: $dot_val"
else
    check_warn "DNS-over-TLS not configured in resolved.conf"
fi

# IPv6 disabled check
ipv6_all=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
if [[ "$ipv6_all" == "1" ]]; then
    check_pass "IPv6 disabled (reduced attack surface)"
else
    check_warn "IPv6 enabled (larger attack surface, ok if needed)"
fi

# Cloudflare tunnel
if systemctl is-active cloudflared &>/dev/null; then
    check_pass "Cloudflare Tunnel active (no direct port exposure)"
else
    check_warn "Cloudflare Tunnel not running"
fi

# TLS certificates
for domain in immich.mkjh.dk admin.mkjh.dk; do
    expiry=$(echo | timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [[ -n "$expiry" ]]; then
        exp_epoch=$(date -d "$expiry" +%s 2>/dev/null)
        now_epoch=$(date +%s)
        days_left=$(( (exp_epoch - now_epoch) / 86400 ))
        if [[ $days_left -gt 14 ]]; then
            check_pass "$domain TLS cert valid ($days_left days left)"
        elif [[ $days_left -gt 0 ]]; then
            check_warn "$domain TLS cert expiring soon ($days_left days)"
        else
            check_fail "$domain TLS cert expired!"
        fi
    else
        check_warn "$domain TLS cert check failed (unreachable?)"
    fi
done

# Nmap localhost scan (quick, TCP only)
if command -v nmap &>/dev/null; then
    nmap_result=$(nmap -sT -p- --min-rate 5000 localhost 2>/dev/null)
    nmap_open=$(echo "$nmap_result" | grep "^[0-9]" | grep "open" | wc -l)
    check_pass "Localhost port scan complete ($nmap_open open ports)"
    echo "$nmap_result" >> "$LOG_FILE"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. CONTAINER SECURITY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "CONTAINER SECURITY"

if command -v podman &>/dev/null; then
    # Container policy
    if [[ -f /etc/containers/policy.json ]]; then
        if grep -q '"reject"' /etc/containers/policy.json; then
            check_pass "Container policy: default reject (whitelist mode)"
        else
            check_warn "Container policy: not default-reject"
        fi
    else
        check_fail "No container security policy found"
    fi

    # Privileged containers
    priv_containers=$(podman ps --format '{{.Names}}' --filter 'status=running' 2>/dev/null | while read -r name; do
        podman inspect "$name" 2>/dev/null | grep -q '"Privileged": true' && echo "$name"
    done | wc -l)
    [[ $priv_containers -eq 0 ]] && check_pass "No privileged containers running" || check_fail "$priv_containers privileged containers found"

    # Root containers
    root_containers=$(podman ps --format '{{.Names}}' --filter 'status=running' 2>/dev/null | wc -l)
    check_warn "$root_containers rootful containers running (podman rootless preferred)"

    # Container image updates
    outdated=$(podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | head -10)
    log "Running container images: $outdated"
else
    check_warn "Podman not installed"
fi

# Cgroup v2
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    check_pass "Cgroup v2 (unified hierarchy) active"
else
    check_warn "Cgroup v1 detected (v2 recommended)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. PACKAGE & UPDATE SECURITY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "PACKAGES & UPDATES"

# Pacman signature verification
sig_level=$(grep -E '^SigLevel' /etc/pacman.conf 2>/dev/null | head -1)
if echo "$sig_level" | grep -q "Required"; then
    check_pass "Pacman package signatures required ($sig_level)"
elif echo "$sig_level" | grep -q "Never"; then
    check_fail "Pacman signature verification disabled!"
else
    check_warn "Pacman signature level: $sig_level"
fi

# Known vulnerabilities
if command -v arch-audit &>/dev/null; then
    vuln_count=$(arch-audit 2>/dev/null | wc -l)
    if [[ $vuln_count -eq 0 ]]; then
        check_pass "No known vulnerabilities (arch-audit)"
    elif [[ $vuln_count -lt 5 ]]; then
        check_warn "$vuln_count known vulnerabilities"
    else
        check_fail "$vuln_count known vulnerabilities"
    fi
    arch-audit 2>/dev/null >> "$LOG_FILE"
else
    check_warn "arch-audit not available"
fi

# Pending updates
updates=$(pacman -Qu 2>/dev/null | wc -l)
[[ $updates -eq 0 ]] && check_pass "System fully up to date" || check_warn "$updates packages have updates available"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 10. BACKUP & RECOVERY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "BACKUP & RECOVERY"

# Backup timer
if systemctl is-active server-backup.timer &>/dev/null; then
    check_pass "Backup timer active"
    next=$(systemctl show server-backup.timer -p NextElapseUSecRealtime --value 2>/dev/null)
    log "Next backup: $next"
else
    check_fail "Backup timer not active"
fi

# Last backup result
backup_result=$(systemctl show server-backup -p Result --value 2>/dev/null)
if [[ "$backup_result" == "success" ]]; then
    check_pass "Last backup: success"
elif [[ -z "$backup_result" || "$backup_result" == "" ]]; then
    check_warn "No backup has run yet"
else
    check_fail "Last backup: $backup_result"
fi

# rclone B2 connectivity
if command -v rclone &>/dev/null; then
    if rclone lsd b2: &>/dev/null; then
        check_pass "Backblaze B2 connection verified"
    else
        check_fail "Backblaze B2 connection failed"
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. WEB SERVER / CADDY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "WEB SERVER"

if systemctl is-active caddy &>/dev/null; then
    check_pass "Caddy web server running"
else
    check_fail "Caddy not running"
fi

# Caddy config validation
if caddy validate --config /etc/caddy/Caddyfile &>/dev/null; then
    check_pass "Caddy configuration valid"
else
    check_fail "Caddy configuration invalid"
fi

# Admin dashboard auth
if [[ -f /etc/caddy/.auth-credentials ]]; then
    cred_perms=$(stat -c %a /etc/caddy/.auth-credentials 2>/dev/null)
    [[ "$cred_perms" == "600" ]] && check_pass "Auth credentials file permissions ok (600)" || check_fail "Auth credentials file too open ($cred_perms)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 12. LYNIS AUDIT (third-party deep scan)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "LYNIS DEEP SCAN"

if command -v lynis &>/dev/null; then
    echo -e "  Running Lynis audit (this takes a moment)..."
    lynis audit system --no-colors --quick --logfile "$LOG_DIR/lynis-$TIMESTAMP.log" --report-file "$LOG_DIR/lynis-report-$TIMESTAMP.dat" &>/dev/null

    if [[ -f "$LOG_DIR/lynis-report-$TIMESTAMP.dat" ]]; then
        lynis_score=$(grep "hardening_index=" "$LOG_DIR/lynis-report-$TIMESTAMP.dat" 2>/dev/null | cut -d= -f2)
        lynis_warnings=$(grep "^warning\[\]=" "$LOG_DIR/lynis-report-$TIMESTAMP.dat" 2>/dev/null | wc -l)
        lynis_suggestions=$(grep "^suggestion\[\]=" "$LOG_DIR/lynis-report-$TIMESTAMP.dat" 2>/dev/null | wc -l)

        if [[ -n "$lynis_score" ]]; then
            if [[ $lynis_score -ge 80 ]]; then
                check_pass "Lynis hardening score: $lynis_score/100"
            elif [[ $lynis_score -ge 60 ]]; then
                check_warn "Lynis hardening score: $lynis_score/100"
            else
                check_fail "Lynis hardening score: $lynis_score/100"
            fi
        fi
        check_warn "Lynis: $lynis_warnings warnings, $lynis_suggestions suggestions (see $LOG_DIR/lynis-report-$TIMESTAMP.dat)"
    else
        check_warn "Lynis report not generated"
    fi
else
    check_warn "Lynis not available"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 13. SECRETS & CREDENTIALS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "SECRETS & CREDENTIALS"

# Check for exposed secrets in common locations
secrets_found=0
for pattern in "PRIVATE_KEY\|API_KEY\|SECRET_KEY\|PASSWORD=" ; do
    hits=$(grep -rl "$pattern" /srv/ /etc/caddy/ /home/ 2>/dev/null | grep -v ".auth-credentials\|.env\|config.json\|\.git" | head -5)
    if [[ -n "$hits" ]]; then
        ((secrets_found++))
        log "Potential secrets in: $hits"
    fi
done
[[ $secrets_found -eq 0 ]] && check_pass "No exposed secrets in /srv /etc/caddy /home" || check_warn "Possible secrets found in $secrets_found locations (check log)"

# Environment files permissions
for envfile in /srv/vault/03-personal/04-secrets/addons.env /etc/environment; do
    if [[ -f "$envfile" ]]; then
        ep=$(stat -c %a "$envfile" 2>/dev/null)
        if [[ "$ep" -le 600 ]]; then
            check_pass "$envfile permissions ok ($ep)"
        else
            check_warn "$envfile permissions too open ($ep)"
        fi
    fi
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
separator

SCORE=0
[[ $TOTAL -gt 0 ]] && SCORE=$(( (PASSED * 100) / TOTAL ))

echo -e "${BOLD}Security Audit Summary${NC}"
echo -e "  Passed:   ${GREEN}${PASSED}${NC}"
echo -e "  Failed:   ${RED}${FAILED}${NC}"
echo -e "  Warnings: ${YELLOW}${WARNINGS}${NC}"
echo -e "  Total:    ${TOTAL}"
echo ""

if [[ $SCORE -ge 80 ]]; then
    echo -e "  Score: ${GREEN}${SCORE}%${NC} ✓"
elif [[ $SCORE -ge 60 ]]; then
    echo -e "  Score: ${YELLOW}${SCORE}%${NC} !"
else
    echo -e "  Score: ${RED}${SCORE}%${NC} ✗"
fi

echo ""
echo -e "  Log:    ${BLUE}$LOG_FILE${NC}"
echo -e "  Lynis:  ${BLUE}$LOG_DIR/lynis-report-$TIMESTAMP.dat${NC}"

separator

# ── JSON report ─────────────────────────────────────────────
cat > "$JSON_FILE" << ENDJSON
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "kernel": "$(uname -r)",
  "score": $SCORE,
  "passed": $PASSED,
  "failed": $FAILED,
  "warnings": $WARNINGS,
  "total": $TOTAL,
  "log_file": "$LOG_FILE",
  "lynis_score": "${lynis_score:-n/a}"
}
ENDJSON

log ""
log "Score: $SCORE% (Passed: $PASSED, Failed: $FAILED, Warnings: $WARNINGS)"

# ── Cleanup third-party tools ──────────────────────────────
pkg_cleanup

echo ""
echo -e "${GREEN}Done.${NC} All audit tools removed. Results saved to $LOG_DIR/"
