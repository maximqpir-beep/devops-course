#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "[OK] $desc"
        ((PASS+=1))
    else
        echo "[FAIL] $desc (expected=$expected, actual=$actual)"
        ((FAIL+=1))
    fi
}

if ! SSH_CONFIG=$(sudo /usr/sbin/sshd -T); then
    echo "[FAIL] Cannot read SSH configuration"
    exit 1
fi

if ! UFW_STATUS=$(sudo env LC_ALL=C ufw status verbose); then
    echo "[FAIL] Cannot read UFW configuration"
    exit 1
fi

echo "Audit: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] SSH"
check "Root login disabled" no \
    "$(awk '$1=="permitrootlogin"{print $2}' <<< "$SSH_CONFIG")"
check "Password authentication disabled" no \
    "$(awk '$1=="passwordauthentication"{print $2}' <<< "$SSH_CONFIG")"
check "SSH port differs from 22" yes \
    "$(awk '$1=="port"{n++; if($2==22) bad=1} END{print (n>0 && !bad)?"yes":"no"}' <<< "$SSH_CONFIG")"
check "MaxAuthTries equals 3" 3 \
    "$(awk '$1=="maxauthtries"{print $2}' <<< "$SSH_CONFIG")"

echo "[2] Firewall"
check "UFW active" active \
    "$(awk '/^Status:/{print $2}' <<< "$UFW_STATUS")"
check "Default incoming policy is deny" yes \
    "$(awk '/^Default:/{if($0 ~ /deny \(incoming\)/) ok=1} END{print ok?"yes":"no"}' <<< "$UFW_STATUS")"

echo "[3] User accounts"
awk -F: '$3>=1000 && $3<65534 {printf "%s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Web server"
check "Nginx service active" active "$(systemctl is-active nginx 2>/dev/null || true)"
if sudo nginx -t >/dev/null 2>&1; then
    nginx_config=ok
else
    nginx_config=fail
fi
check "Nginx configuration syntax" ok "$nginx_config"

cert_min_seconds="${CERT_MIN_SECONDS:-2592000}"
if openssl x509 -in /etc/ssl/certs/devops.crt -checkend "$cert_min_seconds" -noout >/dev/null 2>&1; then
    cert_valid=yes
else
    cert_valid=no
fi
check "Certificate valid for at least 30 days" yes "$cert_valid"

if find /var/www/devops-site -perm -o+w -print -quit | grep -q .; then
    web_files_writable=yes
else
    web_files_writable=no
fi
key_mode=$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || echo missing)
if [[ "$web_files_writable" == no && "$key_mode" == 600 ]]; then
    web_permissions=secure
else
    web_permissions=insecure
fi
check "No world-writable web paths and private key mode 600" secure "$web_permissions"

echo "Passed: $PASS; Failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
