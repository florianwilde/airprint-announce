#!/usr/bin/env bash
# Install-Skript aus diesem Repo laden statt aus community-scripts/ProxmoxVE.
# Bei lokalem Aufruf hat der Clone-Ordner Vorrang (COMMUNITY_SCRIPTS_ROOT, setzt die Engine).
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/florianwilde/airprint-announce/main}"
export COMMUNITY_SCRIPTS_URL
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
# shellcheck disable=SC1090 # Engine wird zur Laufzeit lokal oder remote geladen
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2026 Florian Wilde (Florian Wilde IT SysOp)
# Author: Florian Wilde
# License: MIT | https://github.com/florianwilde/airprint-announce/raw/main/LICENSE
# Source: https://github.com/florianwilde/airprint-announce
# Built on the community-scripts framework: https://github.com/community-scripts/core

# Variablen werden von der Engine (build.func) ausgewertet.
# shellcheck disable=SC2034
APP="AirPrint-Announce"
var_tags="${var_tags:-printing;airprint;mdns}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -x /usr/local/bin/airprint-announce ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated $APP LXC"

  msg_info "Updating airprint-announce tool"
  local tool_tmp
  tool_tmp="$(mktemp)"
  if curl -fsSL "${COMMUNITY_SCRIPTS_URL}/tools/airprint-announce" -o "$tool_tmp" && [[ -s "$tool_tmp" ]]; then
    install -m 0755 "$tool_tmp" /usr/local/bin/airprint-announce
    msg_ok "Updated airprint-announce tool"
  else
    msg_warn "Tool konnte nicht geladen werden, behalte vorhandene Version"
  fi
  rm -f "$tool_tmp"

  msg_info "Refreshing printer announcements"
  if $STD airprint-announce refresh; then
    msg_ok "Refreshed printer announcements"
  else
    msg_warn "Nicht alle Drucker konnten aktualisiert werden (airprint-announce status)"
  fi
  msg_ok "Updated successfully!"
  exit
}

_ap_valid_ip() {
  [[ "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local octet
  for octet in "${BASH_REMATCH[@]:1}"; do
    ((10#$octet <= 255)) || return 1
  done
}

start

# Ab hier nur auf dem Proxmox-Host (im Container endet start in update_script).
if [[ -z "${AIRPRINT_PRINTER_IP:-}" ]]; then
  while true; do
    if ! AIRPRINT_PRINTER_IP="$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "AirPrint-Announce" \
      --inputbox "IP-Adresse des Netzwerkdruckers:" 9 60 "10.0.50.155" 3>&1 1>&2 2>&3)"; then
      msg_error "Abgebrochen."
      exit 0
    fi
    _ap_valid_ip "$AIRPRINT_PRINTER_IP" && break
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "AirPrint-Announce" \
      --msgbox "Ungültige IP-Adresse: ${AIRPRINT_PRINTER_IP}" 8 60
  done
fi
if [[ -z "${AIRPRINT_PRINTER_NAME+x}" ]]; then
  if ! AIRPRINT_PRINTER_NAME="$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "AirPrint-Announce" \
    --inputbox "Anzeigename auf iPhone/iPad:" 9 60 "Kyocera TASKalfa 352ci" 3>&1 1>&2 2>&3)"; then
    msg_error "Abgebrochen."
    exit 0
  fi
fi
export AIRPRINT_PRINTER_IP AIRPRINT_PRINTER_NAME

# Lokaler Aufruf aus einem Clone: das Tool mitgeben, damit der Container die lokale
# Version installiert und nicht die aus dem GitHub-Repo. Einzige Quelle bleibt tools/.
_ap_tool="$(dirname "${BASH_SOURCE[0]:-}")/../tools/airprint-announce"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$_ap_tool" ]]; then
  AIRPRINT_TOOL_B64="$(base64 -w0 "$_ap_tool")"
  export AIRPRINT_TOOL_B64
fi
unset _ap_tool

echo -e "${INFO}${YW}Drucker: ${BGN}${AIRPRINT_PRINTER_IP}${CL}${YW} – Name: ${BGN}${AIRPRINT_PRINTER_NAME:-<Modell vom Drucker>}${CL}"
echo -e "${INFO}${YW}Wichtig: Der Container muss im selben Netz/VLAN wie die iPhones/iPads hängen,${CL}"
echo -e "${INFO}${YW}sonst kommt die Bonjour-Ankündigung nicht an (Bridge/VLAN-Tag über \"Advanced Settings\").${CL}"

build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Verwaltung im Container (pct enter ${CTID}):${CL}"
echo -e "${TAB}${GN}airprint-announce list${CL}                 angekündigte Drucker"
echo -e "${TAB}${GN}airprint-announce status${CL}               Avahi-Status und sichtbare IPP-Dienste"
echo -e "${TAB}${GN}airprint-announce add <IP> [\"Name\"]${CL}    Drucker hinzufügen"
echo -e "${TAB}${GN}airprint-announce remove <IP>${CL}          Drucker entfernen"
echo -e "${TAB}${GN}airprint-announce refresh${CL}              alle Drucker neu abfragen"
