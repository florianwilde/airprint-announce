# airprint-announce

Proxmox-VE-Installer im Stil von [community-scripts](https://community-scripts.org): Ein Einzeiler legt einen kleinen Debian-LXC an, der einen Netzwerkdrucker **stellvertretend per Bonjour/mDNS als AirPrint-Drucker ankündigt**.

iPhones und iPads finden den Drucker dann automatisch und drucken **direkt per IPP/IPPS auf den Drucker**. Im Container läuft kein CUPS-Druckserver, er macht nur die Ankündigung (Avahi).

Typischer Anwendungsfall: Der Drucker beherrscht AirPrint (manuelles Hinzufügen per IP am Mac klappt), seine eigene Bonjour-Ankündigung kommt aber nicht bei den Geräten an. Getestet mit einem Kyocera TASKalfa 352ci.

## Installation

Auf dem Proxmox-VE-Host als root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/florianwilde/airprint-announce/main/ct/airprint-announce.sh)"
```

Das Skript fragt nach Drucker-IP und Anzeigenamen und erstellt dann den Container (Debian 13, unprivilegiert, 1 CPU, 256 MB RAM, 2 GB Disk).

> **Wichtig:** Der Container muss im selben Netz/VLAN wie die iPhones/iPads hängen. mDNS wird nicht geroutet. Bridge und VLAN-Tag lassen sich im Installer über **„Advanced Settings“** einstellen.

### Lokal aus einem Clone

```bash
git clone https://github.com/florianwilde/airprint-announce.git
```

```bash
cd airprint-announce && bash ct/airprint-announce.sh
```

Dabei werden `install/` und `tools/` aus dem lokalen Ordner verwendet (die community-scripts-Engine erkennt den Clone über `COMMUNITY_SCRIPTS_ROOT`).

### Ohne Rückfragen

Die Drucker-Abfragen entfallen, wenn die Werte als Umgebungsvariablen gesetzt sind. Die Container-Defaults lassen sich über die üblichen `var_*`-Variablen überschreiben; `mode=default` überspringt den Einstellungsdialog der Engine:

```bash
AIRPRINT_PRINTER_IP=10.0.50.155 AIRPRINT_PRINTER_NAME="Kyocera TASKalfa 352ci" mode=default bash -c "$(curl -fsSL https://raw.githubusercontent.com/florianwilde/airprint-announce/main/ct/airprint-announce.sh)"
```

| Variable | Bedeutung | Default |
|---|---|---|
| `AIRPRINT_PRINTER_IP` | IP des Druckers | Abfrage, Vorschlag `10.0.50.155` |
| `AIRPRINT_PRINTER_NAME` | Anzeigename auf iPhone/iPad (leer = Modellname vom Drucker) | Abfrage, Vorschlag `Kyocera TASKalfa 352ci` |
| `var_cpu`, `var_ram`, `var_disk` | Ressourcen | `1`, `256`, `2` |
| `var_os`, `var_version` | Betriebssystem | `debian`, `13` |
| `var_unprivileged` | Unprivilegierter Container | `1` |
| `var_tags` | Proxmox-Tags | `printing;airprint;mdns` |
| `COMMUNITY_SCRIPTS_URL` | Quelle für `install/` und `tools/` (z. B. eigener Fork/Branch) | dieses Repo, Branch `main` |

## Verwaltung im Container

```bash
pct enter <CTID>
```

| Befehl | Funktion |
|---|---|
| `airprint-announce add <IP> ["Name"]` | Drucker abfragen und ankündigen (mehrere Drucker möglich) |
| `airprint-announce remove <IP>` | Ankündigung entfernen |
| `airprint-announce refresh` | Alle Drucker neu abfragen (z. B. nach Firmware-Update) |
| `airprint-announce list` | Angekündigte Drucker anzeigen |
| `airprint-announce status` | Avahi-Status und sichtbare `_ipp._tcp`-Dienste |

Ein Update des Containers (Pakete, Tool, `refresh`) erfolgt wie bei community-scripts üblich mit `update` im Container.

## Funktionsweise

1. `airprint-announce add` fragt den Drucker per `ipptool` mit `Get-Printer-Attributes` unter `ipp://<IP>/ipp/print` ab (Modell, UUID, Standort, Dokumentformate, URF, Farbe, Duplex).
2. In `/etc/avahi/hosts` wird ein statischer mDNS-Host `airprint-<ip-mit-bindestrichen>.local` → `<IP>` angelegt. Der eigene Name verhindert Konflikte mit dem Namen, den der Drucker selbst eventuell verwendet.
3. In `/etc/avahi/services/airprint-announce-<ip>.service` werden zwei Dienste auf diesen Host veröffentlicht:
   - `_ipp._tcp` Port 631 mit Subtyp `_universal._sub._ipp._tcp`
   - `_ipps._tcp` Port 443 mit Subtyp `_universal._sub._ipps._tcp`
   - TXT-Records nach AirPrint-Konvention (`rp=ipp/print`, `ty`, `product`, `note`, `pdl`, `URF`, `Color`, `Duplex`, `UUID`, `TLS=1.2`, …). `pdl` enthält nur `application/pdf`, `image/urf`, `image/pwg-raster` und `image/jpeg`, damit der Eintrag unter 255 Byte bleibt.
4. `avahi-daemon` wird neu gestartet. iOS sieht den Drucker und spricht ihn danach direkt per IPP/IPPS an.

Beim Einrichten des Containers wird in `/etc/avahi/avahi-daemon.conf` `rlimit-nproc` auskommentiert (sonst startet Avahi in unprivilegierten LXC nicht) und `publish-workstation=no` gesetzt.

## Fehlersuche

- **Erreicht der Container den Drucker per IPP?** Im Container:

  ```bash
  ipptool -tv ipp://10.0.50.155/ipp/print get-printer-attributes.test
  ```

  Schlägt das fehl, liegt es an Netz/Firewall oder an IPP-Einstellungen am Drucker (IPP aktiv, IP-Filter).
- **Zeigt `airprint-announce status` den Drucker, das iPhone aber nicht?** Dann liegt es fast immer am Netz zwischen Container und iPhone:
  - WLAN filtert Multicast/mDNS oder hat Client-Isolation aktiv (Gast-WLAN, „Multicast-Optimierung“, „mDNS-Filter“ am Access Point).
  - Container und iPhone hängen in **unterschiedlichen VLANs/Subnetzen**. Bridge bzw. VLAN-Tag des Containers anpassen (Proxmox: Container → Netzwerk) oder einen mDNS-Reflector/-Gateway zwischen den VLANs einrichten.
- **Avahi startet nicht:** `journalctl -u avahi-daemon` prüfen; `rlimit-nproc` muss in `/etc/avahi/avahi-daemon.conf` auskommentiert sein.
- **Drucker erscheint, Druck schlägt fehl:** Am Drucker IPP und IPP over SSL/TLS (Port 443) aktiv lassen; prüfen, ob `airprint-<ip>.local` aufgelöst wird (`avahi-resolve -n airprint-10-0-50-155.local`).
- **Warnung „urf-supported fehlt“:** Der Drucker meldet kein URF; es wird ein konservativer Fallback (`V1.4,CP1,W8,SRGB24,RS300,DM1,IS1`) verwendet.

## Entwicklung

```bash
shellcheck -x ct/*.sh install/*.sh tools/airprint-announce tests/*.sh
```

```bash
bash tests/run-tests.sh
```

Die Tests verwenden ein gemocktes `ipptool` und ein temporäres `AVAHI_DIR`. Ist `AVAHI_DIR` auf einen anderen Pfad als `/etc/avahi` gesetzt, läuft das Tool im Testmodus (kein root nötig, kein Neustart von Avahi).

Aufbau:

- `ct/airprint-announce.sh` – Host-Skript (Container-Defaults, Abfragen, Aufruf der Engine)
- `install/airprint-announce-install.sh` – läuft im Container (Avahi, Tool, erster Drucker)
- `tools/airprint-announce` – Verwaltungstool (einzige Quelle; wird beim Installieren in den Container kopiert)

Die Container-Erstellung übernimmt das [community-scripts-Framework](https://github.com/community-scripts/core) (MIT).

## Lizenz

MIT – © 2026 Florian Wilde (Florian Wilde IT SysOp), siehe [LICENSE](LICENSE).
