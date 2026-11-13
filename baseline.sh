#!/usr/bin/env bash
# harden_linux.sh -- low-risk hardening + detection helper. DRY RUN unless you pass "apply".
#   sudo bash harden_linux.sh          report only, shows what it would change
#   sudo bash harden_linux.sh apply    back up configs, then add auditd watch rules
# Never touches passwords, firewall, sshd_config, users, or any service.
set -u
MODE=${1:-plan}
BK=/var/tmp/.hb-$(date +%H%M%S)

echo "== REPORT (needs a human decision; nothing is changed) =="
echo "-- UID 0 accounts other than root:";    awk -F: '$3==0 && $1!="root"{print "  "$1}' /etc/passwd
echo "-- accounts with an empty password:";   awk -F: '$2==""{print "  "$1}' /etc/shadow
echo "-- NOPASSWD sudo rules:";               grep -rEn 'NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | sed 's/^/  /'
echo "-- authorized_keys files:";             ls -l /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null | sed 's/^/  /'
echo "-- world-writable files in cron dirs:"; find /etc/cron* /var/spool/cron -xdev -type f -perm -0002 2>/dev/null | sed 's/^/  /'
echo "-- executables in /tmp /var/tmp /dev/shm (your own scripts will show here):"
find /tmp /var/tmp /dev/shm -xdev -type f -perm /111 2>/dev/null | sed 's/^/  /'
echo "-- listening ports:";                   ss -tuln | sed 's/^/  /'
echo
echo "== CHANGES ($MODE) =="
if [ "$MODE" = apply ]; then
  mkdir -p "$BK" && cp -a /etc/passwd /etc/group /etc/sudoers /etc/sudoers.d /etc/ssh /etc/cron.d /etc/crontab "$BK"/ 2>/dev/null
  echo "  config backup: $BK"
else
  echo "  would back up passwd, group, sudoers, ssh, cron.d to $BK"
fi

if command -v auditctl >/dev/null 2>&1; then
  RULES=/etc/audit/rules.d/50-blueteam.rules
  tmp=$(mktemp)
  for p in /etc/passwd:bt_accounts /etc/shadow:bt_accounts /etc/group:bt_accounts \
           /etc/sudoers:bt_priv /etc/sudoers.d:bt_priv \
           /etc/cron.d:bt_persist /etc/crontab:bt_persist /var/spool/cron:bt_persist \
           /etc/systemd/system:bt_persist /etc/ssh/sshd_config:bt_ssh /root/.ssh:bt_ssh; do
    path=${p%%:*}; key=${p##*:}
    [ -e "$path" ] && echo "-w $path -p wa -k $key" >>"$tmp"
  done
  echo "  auditd watch rules ($(wc -l <"$tmp") paths) -> $RULES"
  if [ "$MODE" = apply ]; then
    install -m 0640 "$tmp" "$RULES" && { augenrules --load >/dev/null 2>&1 || auditctl -R "$RULES" >/dev/null 2>&1; }
    echo "  loaded; verify with: auditctl -l | grep bt_"
  fi
  rm -f "$tmp"
else
  echo "  auditd is not installed on this host: skipped"
fi
