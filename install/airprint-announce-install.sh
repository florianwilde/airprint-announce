#!/usr/bin/env bash

# Copyright (c) 2026 Florian Wilde (Florian Wilde IT SysOp)
# Author: Florian Wilde
# License: MIT | https://github.com/florianwilde/airprint-announce/raw/main/LICENSE
# Source: https://github.com/florianwilde/airprint-announce

# shellcheck disable=SC1091 # Funktionen liefert die Engine über FUNCTIONS_FILE_PATH
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y avahi-daemon avahi-utils cups-ipp-utils
msg_ok "Installed Dependencies"

msg_info "Configuring Avahi for LXC"
# rlimit-nproc verhindert den Start von avahi-daemon in (unprivilegierten) LXC.
sed -i -E 's/^[[:space:]]*(rlimit-nproc[[:space:]]*=.*)$/#\1/' /etc/avahi/avahi-daemon.conf
if grep -qE '^[#[:space:]]*publish-workstation[[:space:]]*=' /etc/avahi/avahi-daemon.conf; then
  sed -i -E 's/^[#[:space:]]*publish-workstation[[:space:]]*=.*$/publish-workstation=no/' /etc/avahi/avahi-daemon.conf
else
  sed -i -E 's/^\[publish\][[:space:]]*$/[publish]\npublish-workstation=no/' /etc/avahi/avahi-daemon.conf
fi
systemctl enable -q avahi-daemon
systemctl restart avahi-daemon
msg_ok "Configured Avahi for LXC"

msg_info "Installing airprint-announce tool"
if [[ -n "${AIRPRINT_TOOL_B64:-}" ]]; then
  base64 -d <<<"$AIRPRINT_TOOL_B64" >/usr/local/bin/airprint-announce
elif ! curl -fsSL "${COMMUNITY_SCRIPTS_URL:?COMMUNITY_SCRIPTS_URL nicht gesetzt}/tools/airprint-announce" -o /usr/local/bin/airprint-announce; then
  msg_error "Konnte ${COMMUNITY_SCRIPTS_URL}/tools/airprint-announce nicht laden"
  exit 1
fi
if [[ ! -s /usr/local/bin/airprint-announce ]] || ! head -n 1 /usr/local/bin/airprint-announce | grep -q '^#!.*bash'; then
  msg_error "airprint-announce ist leer oder ungültig"
  exit 1
fi
chmod 0755 /usr/local/bin/airprint-announce
msg_ok "Installed airprint-announce tool"

if [[ -z "${AIRPRINT_PRINTER_IP:-}" ]]; then
  read -r -p "${TAB3}IP-Adresse des Druckers (leer = später): " AIRPRINT_PRINTER_IP || true
fi
if [[ -n "${AIRPRINT_PRINTER_IP:-}" ]]; then
  msg_info "Announcing printer ${AIRPRINT_PRINTER_IP}"
  if $STD airprint-announce add "$AIRPRINT_PRINTER_IP" "${AIRPRINT_PRINTER_NAME:-}"; then
    msg_ok "Announced printer ${AIRPRINT_PRINTER_IP}"
  else
    msg_warn "Drucker ${AIRPRINT_PRINTER_IP} konnte nicht abgefragt werden. Später nachholen mit: airprint-announce add <IP> [\"Name\"]"
  fi
else
  msg_warn "Kein Drucker angegeben. Später hinzufügen mit: airprint-announce add <IP> [\"Name\"]"
fi

motd_ssh
customize
cleanup_lxc
