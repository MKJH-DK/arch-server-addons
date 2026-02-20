# INSTRUKTION: Opret Arch Server Addons Projekt

## KONTEKST - HVAD DER ALLEREDE EKSISTERER

### Base-repo: `arch-server` (humethix/arch-server på GitHub)

Et komplet Arch Linux server-installationsprojekt med to faser:

**Fase 1 - Pre-install** (`src/install.sh`, ~1700 linjer):
- Kører fra Arch ISO
- LUKS2 fuld disk-kryptering (AES-XTS-512, Argon2id)
- Btrfs med subvolumes (@, @home, @log, @containers, @snapshots) og zstd kompression
- systemd-boot + UKI (Unified Kernel Images) - IKKE GRUB
- Secure Boot forberedelse med sbctl
- TPM 2.0 auto-unlock forberedelse (PCR 7)
- NetworkManager med Ethernet (route-metric 100) og WiFi (route-metric 600)
- SSH opsætning med auto-discovery af nøgler
- Kopierer hele projektet til `/root/arch/` på den nye server

**Fase 2 - Post-install** (`scripts/deploy.sh` → Ansible):
Kører `ansible-playbook playbooks/site.yml` der eksekverer disse roles i rækkefølge:

1. **base_hardening** - 65 sysctl parametre, SSH hardening, kernel modul blacklisting
2. **security_stack** - nftables firewall (default DROP, Cloudflare IP sets, rate limiting), AppArmor, auditd
3. **container_runtime** - Podman med rootless support, CNI networking
4. **cloudflare** - Automatisk Cloudflare IP opdatering via systemd timer
5. **webserver** - Caddy fra officielle Arch repos (`pacman -S caddy`)
6. **monitoring** - htop, iotop, sysstat, journald config, Prometheus Node Exporter (valgfrit)
7. **safe_updates** - Snapper Btrfs snapshots med pacman hooks

### Kritiske stier på serveren (efter deployment)

```
/etc/caddy/Caddyfile              # Hoved Caddy-konfiguration (BASE - rør ikke)
/etc/caddy/conf.d/*.caddy         # ADDON Caddy configs - auto-importeret af base
/srv/www/                         # Default website root (base)
/srv/                             # Parent for addon data-mapper
/etc/nftables.conf                # Firewall regler (Cloudflare-only + SSH rate limit)
/etc/systemd/system/              # Systemd service filer
/usr/local/bin/                   # Scripts og binaries
/usr/local/bin/health-check       # System health check (45+ checks)
/root/arch/                       # Base-projekt kopi på serveren
```

### Caddy base-konfiguration (Jinja2 template-baseret)

Caddyfile genereres fra `src/ansible/roles/webserver/templates/Caddyfile.j2` og understøtter multi-domain.

**Uden domæner (HTTP-only mode):**
```caddy
{
  admin 127.0.0.1:2019
}

import /etc/caddy/conf.d/*.caddy

:80 {
  root * /srv/www
  file_server
  encode gzip zstd
  # ... security headers, logging, health endpoint
}
```

**Med domæner (auto-HTTPS):**
```caddy
{
  admin 127.0.0.1:2019
  email user@example.com
}

import /etc/caddy/conf.d/*.caddy

example.com {
  root * /srv/www
  # ... HSTS, security headers, per-domain logging
}

blog.example.com {
  root * /srv/blog
  # ... same structure, separate log file
}
```

**VIGTIGT**: `import /etc/caddy/conf.d/*.caddy` er DET der gør addon-integration mulig. Ethvert `.caddy` fil i den mappe bliver automatisk loaded. Denne import-linje er ALTID til stede, uanset om der er domæner konfigureret eller ej.

### Multi-domain arkitektur

Base-serveren understøtter flere domæner på samme server:
- Konfigureres via `DOMAINS` env var (kommasepareret) eller `domains` liste i Ansible inventory
- Hvert domæne får automatisk HTTPS via Let's Encrypt
- Hvert domæne har sin egen web root (default: `/srv/www/`) og logfil
- Cloudflare tunnel understøtter også multi-domain (ingress rules per domæne)
- Backward kompatibel: enkelt `DOMAIN` env var konverteres automatisk

**Ansible variabel-format:**
```yaml
domains:
  - { domain: "example.com" }                          # bruger /srv/www
  - { domain: "blog.example.com", root: "/srv/blog" }  # custom root
```

Addons kan tjekke `domains` variablen for at beslutte om de skal bruge et subdomain eller en path-baseret URL.

### Firewall-kontekst

nftables er konfigureret med:
- Default DROP policy
- Cloudflare IPv4+IPv6 IP sets (opdateres ugentligt)
- Port 80 + 443 tilladt fra Cloudflare IPs
- Port 80 + 443 også tilladt direkte (for test - kan fjernes efter tunnel setup)
- Port 443 UDP (QUIC/HTTP3) tilladt
- SSH rate limited (3 nye forbindelser/minut)
- Container networking (podman/CNI interfaces) tilladt
- Localhost altid tilladt

### Netværk

- NetworkManager bruges
- Ethernet: route-metric 100 (altid foretrukket)
- WiFi: route-metric 600 (automatisk fallback)
- Begge forbindelser er aktive samtidig
- Syncthing, rsync og andre sync-tjenester fungerer over begge

### Btrfs subvolumes

```
@            → /           (root)
@home        → /home       (brugerdata)
@log         → /var/log    (logs)
@containers  → /var/lib/containers (Podman)
@snapshots   → /.snapshots (Snapper)
```

### Sikkerhedsgrænser som addons SKAL respektere

- AppArmor er aktivt - nye services bør have profiler
- auditd logger sikkerhedshændelser
- systemd services bør bruge: NoNewPrivileges=yes, PrivateTmp=yes, ProtectSystem=strict (med ReadWritePaths for nødvendige stier)
- Podman kører rootless - containere har IKKE root
- Firewall er Cloudflare-only mode - direkte trafik blokeres (undtagen SSH og test)

---

## OPGAVE: OPRET ADDON-REPO

### Repo navn: `arch-server-addons` (humethix/arch-server-addons)

### Formål
Udvidelser til base-serveren der IKKE ændrer base-repoen. Primært fokus:

1. **Obsidian som website** - Obsidian .md filer serveret som statisk website via Caddy
   - Sync mellem: Windows PC, Android telefon, Arch server
   - Syncthing er den oplagte sync-mekanisme (open source, P2P, krypteret)
   - Caddy serverer vault som website med markdown rendering

2. **Backblaze B2 backup** (nice-to-have) - Offsite backup af serverdata
   - Btrfs snapshots → Backblaze B2 bucket
   - Planlagt via systemd timer

3. **cgit** (git web viewer) - Allerede fjernet fra base, kan genimplementeres som addon
   - cgit + fcgiwrap + Caddy reverse proxy

### Projektstruktur (OPRET DENNE)

```
arch-server-addons/
├── addons/                        # Individuelle addon-moduler
│   ├── obsidian-web/              # Obsidian som website
│   │   ├── tasks/main.yml         # Ansible tasks
│   │   ├── handlers/main.yml      # Service handlers
│   │   ├── templates/
│   │   │   ├── obsidian.caddy.j2  # Caddy config for Obsidian site
│   │   │   └── syncthing-config.xml.j2  # Syncthing device config
│   │   ├── files/
│   │   │   └── obsidian-render.sh # Markdown → HTML rendering script
│   │   └── defaults/main.yml      # Default variabler
│   │
│   ├── backblaze-backup/          # Backblaze B2 backup
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   └── b2-backup.sh.j2    # Backup script
│   │   ├── files/
│   │   └── defaults/main.yml
│   │
│   └── cgit/                      # Git web viewer (fra base-repo)
│       ├── tasks/main.yml
│       ├── handlers/main.yml
│       ├── templates/
│       │   ├── cgitrc.j2
│       │   └── cgit.caddy.j2
│       └── defaults/main.yml
│
├── ansible/
│   ├── playbooks/
│   │   ├── addons.yml             # Hoved-playbook (kører ALLE aktiverede addons)
│   │   └── obsidian.yml           # Kun Obsidian addon
│   └── inventory/
│       └── addons.yml             # Addon-specifikke variabler
│
├── scripts/
│   ├── deploy-addons.sh           # Master addon deployment script
│   └── sync-status.sh             # Vis Syncthing sync status
│
├── config/
│   └── addons.env                 # Addon konfiguration (bruger-editerbar)
│
├── .gitignore
├── README.md
├── CHANGELOG.md
└── LICENSE                        # MIT (samme som base)
```

### DETALJERET SPECIFIKATION PER ADDON

---

#### ADDON 1: Obsidian Web (`addons/obsidian-web/`)

**Mål**: Obsidian vault synces til serveren og serveres som statisk website.

**Sync-arkitektur**:
```
Windows PC (Obsidian)  ←→  Syncthing  ←→  Arch Server (/srv/obsidian/vault/)
Android (Obsidian)     ←→  Syncthing  ←→  Arch Server (/srv/obsidian/vault/)
```

Syncthing køres som systemd user service for den konfigurerede admin-bruger.

**Stier på serveren**:
```
/srv/obsidian/vault/              # Syncthing sync target (rå .md filer)
/srv/obsidian/site/               # Rendered HTML (hvis vi renderer)
/etc/caddy/conf.d/obsidian.caddy  # Caddy config
```

**Caddy config** (`obsidian.caddy.j2`):
Serveren skal kunne servere markdown filer direkte. Caddy har ikke indbygget markdown rendering, så der er to tilgange:

- **Tilgang A (simpel)**: Server `.md` filer som plaintext + et JavaScript markdown library (marked.js/markdown-it) i browseren der renderer on-the-fly. En simpel `index.html` wrapper med JS.
- **Tilgang B (pre-render)**: Et script/tool der konverterer `.md` → `.html`. Kør via inotifywait eller Syncthing hooks.

Anbefaling: **Start med Tilgang A** (simpel, ingen build-step, ændringer vises instant).

**Ansible tasks** skal:
1. Installere Syncthing (`pacman -S syncthing`)
2. Oprette `/srv/obsidian/vault/` og `/srv/obsidian/site/`
3. Enable syncthing som user service: `systemctl --user enable --now syncthing`
4. Deploy Caddy config til `/etc/caddy/conf.d/obsidian.caddy`
5. Deploy en `index.html` wrapper med markdown-it JS library
6. Reload Caddy

**Syncthing konfiguration**:
- Syncthing API kører på `127.0.0.1:8384` (admin interface)
- Brugeren skal manuelt parre enheder via Syncthing UI første gang
- Eller: Forudkonfigurer device IDs i `addons.env`

**Vigtige overvejelser**:
- Syncthing sync er to-vejs - ændringer på serveren synces TILBAGE
- `.obsidian/` mappen (Obsidian settings) bør IKKE serveres som website
- Brug Caddy `handle_path` til at skjule interne mapper
- Rate-limit bør overvejes for public-facing website

---

#### ADDON 2: Backblaze B2 Backup (`addons/backblaze-backup/`)

**Mål**: Automatiseret offsite backup til Backblaze B2.

**Hvad der backes op**:
1. `/srv/` - Alt addon-data (Obsidian vault, git repos, etc.)
2. `/etc/caddy/` - Web server konfiguration
3. Btrfs snapshots fra Snapper (allerede konfigureret i base)
4. `/root/arch/` - Server-konfiguration (valgfrit)

**Backup-strategi**:
```
Daglig: Inkrementel sync af /srv/ til B2
Ugentlig: Fuld snapshot backup
Månedlig: Verifikation af backup-integritet
```

**Værktøj**: `rclone` (bedre end b2 CLI, understøtter kryptering og mange backends)

**Stier**:
```
/usr/local/bin/server-backup       # Backup script
/etc/systemd/system/server-backup.service  # Oneshot service
/etc/systemd/system/server-backup.timer    # Timer (daglig)
/srv/backups/staging/              # Lokal staging (snapshot mount)
```

**Ansible tasks** skal:
1. Installere rclone (`pacman -S rclone`)
2. Deploy backup script
3. Deploy systemd service + timer
4. Enable timer
5. Konfiguration af B2 credentials sker manuelt af brugeren via `rclone config`

**Konfiguration** (`addons.env`):
```bash
BACKUP_ENABLED=true
BACKUP_B2_BUCKET="my-server-backup"
BACKUP_SCHEDULE="daily"           # daily, weekly
BACKUP_RETENTION_DAYS=30
BACKUP_ENCRYPT=true               # rclone crypt
BACKUP_PATHS="/srv /etc/caddy"
```

---

#### ADDON 3: cgit (`addons/cgit/`)

**Mål**: Lightweight git web viewer (flyttet fra base-repo).

NOTE: Denne addon er allerede delvist implementeret - koden blev fjernet fra base-repoen under oprydning. Følgende filer fra det gamle base-repo kan genbruges som reference:
- `src/ansible/roles/cgit/tasks/main.yml` - Ansible tasks
- `src/ansible/roles/cgit/templates/cgitrc.j2` - cgit config
- `src/ansible/roles/cgit/templates/cgit-caddy.j2` - Caddy config

**VIGTIG ÆNDRING**: Den gamle cgit integration brugte `lineinfile` til at indsætte `import` i Caddyfile - det var BROKEN (indsatte inde i global block). Den nye base bruger `import /etc/caddy/conf.d/*.caddy`, så cgit addon skal bare droppe sin config i `/etc/caddy/conf.d/cgit.caddy`. Ingen manipulation af base Caddyfile.

---

### DEPLOY SCRIPT (`scripts/deploy-addons.sh`)

Scriptet skal:
1. Tjekke at base-serveren er deployed (health-check)
2. Læse `config/addons.env` for aktiverede addons
3. Kalde `ansible-playbook` med de relevante roller
4. Verificere at addons er funktionelle
5. Vise status

```bash
#!/bin/bash
# Deploy addons til Arch Server
# Forudsætning: Base-server er deployed via /root/arch/scripts/deploy.sh

# Find project
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check base server
if ! /usr/local/bin/health-check --json | grep -q '"status":"pass"'; then
    echo "ERROR: Base server health check failed. Deploy base first."
    exit 1
fi

# Source addon config
source "$PROJECT_DIR/config/addons.env"

# Run addon playbook
cd "$PROJECT_DIR/ansible"
ansible-playbook -i /root/arch/src/ansible/inventory/hosts.yml \
    playbooks/addons.yml \
    -e "obsidian_enabled=${OBSIDIAN_ENABLED:-false}" \
    -e "backblaze_enabled=${BACKBLAZE_ENABLED:-false}" \
    -e "cgit_enabled=${CGIT_ENABLED:-false}"
```

### ADDON PLAYBOOK (`ansible/playbooks/addons.yml`)

```yaml
---
- name: Deploy Arch Server Addons
  hosts: localhost
  connection: local
  become: yes

  roles:
    - role: ../../addons/obsidian-web
      when: obsidian_enabled | default(false) | bool
      tags: [obsidian]

    - role: ../../addons/backblaze-backup
      when: backblaze_enabled | default(false) | bool
      tags: [backup, backblaze]

    - role: ../../addons/cgit
      when: cgit_enabled | default(false) | bool
      tags: [cgit, git]

  post_tasks:
    - name: Reload Caddy to pick up new configs
      systemd:
        name: caddy
        state: reloaded
      failed_when: false

    - name: Verify addon deployment
      debug:
        msg:
          - "Addon deployment complete"
          - "Obsidian: {{ 'ENABLED' if obsidian_enabled | default(false) | bool else 'disabled' }}"
          - "Backblaze: {{ 'ENABLED' if backblaze_enabled | default(false) | bool else 'disabled' }}"
          - "cgit: {{ 'ENABLED' if cgit_enabled | default(false) | bool else 'disabled' }}"
```

### ADDON KONFIGURATION (`config/addons.env`)

```bash
# Arch Server Addons Configuration
# ============================================================================

# OBSIDIAN WEB
OBSIDIAN_ENABLED=true
OBSIDIAN_VAULT_PATH="/srv/obsidian/vault"
OBSIDIAN_DOMAIN=""                  # Eget domæne (f.eks. "wiki.example.com") eller tom for path-baseret
OBSIDIAN_URL_PREFIX="/wiki"          # URL prefix for path-baseret (når OBSIDIAN_DOMAIN er tom)

# BACKBLAZE BACKUP
BACKBLAZE_ENABLED=false
BACKUP_B2_BUCKET=""
BACKUP_SCHEDULE="daily"
BACKUP_RETENTION_DAYS=30

# CGIT (Git web viewer)
CGIT_ENABLED=false
CGIT_TITLE="My Git Repos"
CGIT_REPO_PATH="/srv/git"
```

---

## WORKFLOW PÅ SERVEREN

Brugeren kører dette efter base-deployment:

```bash
# 1. Clone addon repo
cd /root
git clone https://github.com/humethix/arch-server-addons.git

# 2. Konfigurer addons
cd arch-server-addons
nano config/addons.env

# 3. Deploy addons
chmod +x scripts/deploy-addons.sh
./scripts/deploy-addons.sh

# 4. (Obsidian) Par Syncthing enheder
# Åbn http://localhost:8384 og tilføj Windows/Android device IDs

# 5. Verificer
curl http://localhost/wiki/
/usr/local/bin/health-check
```

---

## GRUNDPRINCIP: BEST PRACTICE ALTID

**Alt kode i dette projekt skal følge best practice. Dette er ikke valgfrit - det er en fast regel.**

Konkret betyder det:

### Kodestandard
- **Shell scripts**: POSIX-kompatibelt hvor muligt, `shellcheck`-clean, `set -euo pipefail`, funktioner med tydelige navne, ingen magic numbers
- **Ansible**: Brug `community.general` moduler frem for `command`/`shell`. Idempotente tasks. Handlers til service reloads. Navngiv ALLE tasks beskrivende. Brug `defaults/main.yml` for variabler med fornuftige defaults
- **YAML**: Konsistent indrykning (2 spaces), ingen trailing whitespace, brug af anchor/alias hvor det reducerer duplikering
- **Caddy configs**: Brug named matchers, undgå wildcards i route paths, log altid, security headers altid
- **Systemd units**: Altid inkludér security hardening (NoNewPrivileges, ProtectSystem, PrivateTmp, ReadWritePaths). Altid Description, After/Wants, Restart policy

### Arkitektur og design
- **Separation of concerns**: Hver addon er selvstændig. Ingen addon afhænger af en anden addon
- **Fail gracefully**: Alle scripts skal håndtere fejl eksplicit. Aldrig `|| true` uden kommentar om hvorfor
- **Idempotens**: Kør deploy 10 gange - resultatet skal være det samme som 1 gang
- **Minimal privilege**: Services kører med mindst mulige rettigheder. Aldrig root medmindre absolut nødvendigt
- **Explicit over implicit**: Ingen antagelser. Dokumentér hvorfor, ikke bare hvad
- **DRY (Don't Repeat Yourself)**: Fælles funktionalitet i shared scripts/variables, ikke copy-paste

### Sikkerhed
- Credentials ALDRIG i kode eller config-filer i repo - brug env vars eller interaktiv input
- Alle netværkstjenester binder til 127.0.0.1 medmindre de specifikt skal være eksterne
- Input validering i alle scripts der tager bruger-input
- File permissions sat eksplicit (ikke default)
- Brug `mktemp` for temp-filer, aldrig hardcoded /tmp stier

### Dokumentation
- Hver addon har en README med: formål, forudsætninger, installation, konfiguration, fejlfinding
- Inline kommentarer forklarer HVORFOR, ikke hvad (koden viser hvad)
- Changelog opdateres ved enhver ændring

### Test-mentalitet
- Valider config-filer før deploy (f.eks. `caddy validate`, `nft -c -f`)
- Verificer at services starter og responderer efter deployment
- Health checks for alle addons

**Når du er i tvivl om en tilgang: vælg den der er mest vedligeholdbar, mest sikker, og nemmest at forstå for en person der ser koden første gang.**

---

## VIGTIGE REGLER

1. **Addon-repo ændrer ALDRIG filer i base-repo** (`/root/arch/`)
2. **Caddy configs går i `/etc/caddy/conf.d/`** - aldrig i `/etc/caddy/Caddyfile`
3. **Brug base-repoens Ansible inventory** (`/root/arch/src/ansible/inventory/hosts.yml`)
4. **Respekter sikkerhedsgrænser** - AppArmor, nftables, auditd
5. **Alle services bruger systemd** med security directives
6. **Stier under `/srv/<addon-name>/`** for addon-data
7. **Ingen hardcoded passwords** - brug environment variabler eller interaktiv config
8. **Test at Caddy reload virker** efter config-ændringer: `caddy validate --config /etc/caddy/Caddyfile`
9. **Følg Arch Wiki** som reference for pakke-konfiguration og systemd best practice
10. **Skriv kode som om den skal læses af andre** - klarhed over klogskab

---

## PRIORITERING VED OPRETTELSE

1. **Først**: Projektstruktur, README, config, deploy script, addons playbook
2. **Derefter**: Obsidian-web addon (primær use case)
3. **Dernæst**: Backblaze backup (nice-to-have)
4. **Til sidst**: cgit addon (genimplementering)

Start med at oprette hele projektstrukturen med placeholders, så addon-repoen er funktionel fra start. Implementér derefter Obsidian-addon fuldt ud som det første rigtige addon.
