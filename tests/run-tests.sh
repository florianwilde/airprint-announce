#!/usr/bin/env bash
# Copyright (c) 2026 Florian Wilde (Florian Wilde IT SysOp)
# License: MIT
#
# Tests für tools/airprint-announce mit gemocktem ipptool und temporärem AVAHI_DIR.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${ROOT}/tools/airprint-announce"
FIXTURE="${ROOT}/tests/fixtures/kyocera-taskalfa-352ci.txt"
IP="10.0.50.155"
OTHER_IP="10.0.50.15"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export AVAHI_DIR="${WORK}/avahi"
mkdir -p "${WORK}/bin" "$AVAHI_DIR"

# Mock: liefert die Kyocera-Ausgabe, protokolliert die Argumente, prüft die .test-Datei.
cat >"${WORK}/bin/ipptool" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${WORK}/ipptool.args"
testfile="\${!#}"
grep -q 'OPERATION Get-Printer-Attributes' "\$testfile" || exit 2
grep -q 'printer-make-and-model,printer-uuid,printer-location,document-format-supported,urf-supported,color-supported,sides-supported' "\$testfile" || exit 2
[[ "\${MOCK_FAIL:-0}" == 1 ]] && { echo "ipptool: Unable to connect" >&2; exit 1; }
cat "${FIXTURE}"
MOCK
chmod +x "${WORK}/bin/ipptool"
export PATH="${WORK}/bin:${PATH}"

PASS=0
FAIL=0
ok() {
  echo "ok   - $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL - $1" >&2
  FAIL=$((FAIL + 1))
}
check() {
  local desc="$1"
  shift
  if "$@"; then ok "$desc"; else fail "$desc"; fi
}
# Erwartet, dass der Befehl fehlschlägt.
fails() {
  ! "$@" >/dev/null 2>&1
}

SERVICE="${AVAHI_DIR}/services/airprint-announce-10-0-50-155.service"
HOSTS="${AVAHI_DIR}/hosts"

# --- add ---------------------------------------------------------------------
"$TOOL" add "$IP" "Kyocera TASKalfa 352ci" >/dev/null
check "add erzeugt Service-Datei" test -f "$SERVICE"
check "ipptool mit -T 15 -tv und ipp://IP/ipp/print aufgerufen" \
  grep -q -- "-T 15 -tv ipp://${IP}/ipp/print " "${WORK}/ipptool.args"
check "Service-Datei ist gültiges XML" xmllint --noout "$SERVICE"
check "Service-Name gesetzt" grep -q '<name replace-wildcards="no">Kyocera TASKalfa 352ci</name>' "$SERVICE"
check "_ipp._tcp auf Port 631" grep -q '<type>_ipp._tcp</type>' "$SERVICE"
check "_ipps._tcp vorhanden" grep -q '<type>_ipps._tcp</type>' "$SERVICE"
check "Port 443 vorhanden" grep -q '<port>443</port>' "$SERVICE"
check "Subtyp universal ipp" grep -q '<subtype>_universal._sub._ipp._tcp</subtype>' "$SERVICE"
check "Subtyp universal ipps" grep -q '<subtype>_universal._sub._ipps._tcp</subtype>' "$SERVICE"
check "host-name zweimal gesetzt" test "$(grep -c '<host-name>airprint-10-0-50-155.local</host-name>' "$SERVICE")" -eq 2
check "Standort XML-escaped" grep -qF '<txt-record>note=Büro &amp; Flur &lt;2. OG&gt; &quot;Süd&quot;</txt-record>' "$SERVICE"
check "ty=Modell" grep -qF '<txt-record>ty=Kyocera TASKalfa 352ci</txt-record>' "$SERVICE"
check "product=(Modell)" grep -qF '<txt-record>product=(Kyocera TASKalfa 352ci)</txt-record>' "$SERVICE"
check "pdl gefiltert" grep -qF '<txt-record>pdl=application/pdf,image/urf,image/pwg-raster,image/jpeg</txt-record>' "$SERVICE"
check "URF übernommen" grep -qF '<txt-record>URF=V1.4,CP1,DM1,FN3-5-11-12-14-20-21-22-23-24-28-31-50-51-52-53,' "$SERVICE"
check "Color=T" grep -qF '<txt-record>Color=T</txt-record>' "$SERVICE"
check "Duplex=T" grep -qF '<txt-record>Duplex=T</txt-record>' "$SERVICE"
check "UUID ohne urn:uuid:" grep -qF '<txt-record>UUID=4509a320-00a0-008f-00b6-002507510eca</txt-record>' "$SERVICE"
check "adminurl" grep -qF '<txt-record>adminurl=http://10.0.50.155/</txt-record>' "$SERVICE"
check "rp=ipp/print" grep -qF '<txt-record>rp=ipp/print</txt-record>' "$SERVICE"
check "TLS=1.2" grep -qF '<txt-record>TLS=1.2</txt-record>' "$SERVICE"
check "hosts-Eintrag" grep -qxF "${IP} airprint-10-0-50-155.local # airprint-announce:${IP}" "$HOSTS"

# --- list --------------------------------------------------------------------
LIST="$("$TOOL" list)"
check "list zeigt IP" grep -q "^${IP} " <<<"$LIST"
check "list zeigt Name" grep -q "Kyocera TASKalfa 352ci" <<<"$LIST"

# --- add mit demselben Drucker: keine Duplikate --------------------------------
"$TOOL" add "$IP" "Kyocera TASKalfa 352ci" >/dev/null
check "kein doppelter hosts-Eintrag" test "$(grep -c "airprint-announce:${IP}\$" "$HOSTS")" -eq 1
check "genau eine Service-Datei" test "$(find "${AVAHI_DIR}/services" -name '*.service' | wc -l)" -eq 1
check "XML nach erneutem add gültig" xmllint --noout "$SERVICE"

# --- Name mit Sonderzeichen und zweiter Drucker (Präfix-IP) ---------------------
"$TOOL" add "$OTHER_IP" 'Flur -- "Kopierer" & <Fax>' >/dev/null
SERVICE2="${AVAHI_DIR}/services/airprint-announce-10-0-50-15.service"
check "zweiter Drucker XML gültig" xmllint --noout "$SERVICE2"
check "zwei hosts-Einträge" test "$(grep -c 'airprint-announce:' "$HOSTS")" -eq 2
LIST="$("$TOOL" list)"
check "list zeigt Sonderzeichen-Namen" grep -qF 'Flur -- "Kopierer" & <Fax>' <<<"$LIST"

# --- refresh -----------------------------------------------------------------
: >"${WORK}/ipptool.args"
"$TOOL" refresh >/dev/null
check "refresh fragt beide Drucker ab" test "$(wc -l <"${WORK}/ipptool.args")" -eq 2
check "refresh behält Namen" grep -q '<name replace-wildcards="no">Flur -- &quot;Kopierer&quot; &amp; &lt;Fax&gt;</name>' "$SERVICE2"

# --- Name-Default und Fehlerfälle --------------------------------------------
"$TOOL" add 10.0.50.200 >/dev/null
check "ohne Name wird Modell verwendet" \
  grep -q '<name replace-wildcards="no">Kyocera TASKalfa 352ci</name>' "${AVAHI_DIR}/services/airprint-announce-10-0-50-200.service"
"$TOOL" remove 10.0.50.200 >/dev/null
check "ungültige IP abgelehnt" fails "$TOOL" add 10.0.50.256
check "nicht erreichbarer Drucker -> Fehler" fails env MOCK_FAIL=1 "$TOOL" add 10.0.50.99
check "keine Datei für nicht erreichbaren Drucker" test ! -e "${AVAHI_DIR}/services/airprint-announce-10-0-50-99.service"

# --- remove ------------------------------------------------------------------
"$TOOL" remove "$OTHER_IP" >/dev/null
check "remove löscht Service-Datei" test ! -e "$SERVICE2"
check "remove lässt anderen Drucker stehen" test -f "$SERVICE"
check "remove entfernt nur passenden hosts-Eintrag" grep -qxF "${IP} airprint-10-0-50-155.local # airprint-announce:${IP}" "$HOSTS"
check "hosts ohne entfernten Drucker" fails grep -q 'airprint-announce:10\.0\.50\.15$' "$HOSTS"
"$TOOL" remove "$IP" >/dev/null
check "remove letzter Drucker" test ! -e "$SERVICE"
check "hosts leer" test "$(grep -c 'airprint-announce:' "$HOSTS" || true)" -eq 0
check "remove unbekannter IP -> Fehler" fails "$TOOL" remove 10.0.50.155
check "list ohne Drucker" grep -q "Keine Drucker" <<<"$("$TOOL" list)"

echo
echo "${PASS} bestanden, ${FAIL} fehlgeschlagen"
((FAIL == 0))
