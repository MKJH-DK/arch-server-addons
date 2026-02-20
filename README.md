# Arch Server Addons

Udvidelser til [arch-server](https://github.com/humethix/arch-server) base installationen.

## Oversigt

Dette repo indeholder addons til Arch Server base installationen. Addons er designet til at udvide funktionaliteten uden at ændre i base-repoen.

### Tilgængelige Addons

1. **Obsidian Web** - Server Obsidian vault som statisk website med Syncthing sync
2. **Backblaze B2 Backup** - Automatisk offsite backup til Backblaze B2
3. **cgit** - Lightweight git web viewer

## Forudsætninger

- Arch Server base installation er deployet via `/root/arch/scripts/deploy.sh`
- Ansible er installeret på serveren
- Serveren har internetadgang

## Installation

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
```

## Konfiguration

Alle addons konfigureres via `config/addons.env`:

```bash
# Aktiver/deaktiver addons
OBSIDIAN_ENABLED=true
BACKBLAZE_ENABLED=false
CGIT_ENABLED=false

# Addon-specifikke indstillinger
OBSIDIAN_VAULT_PATH="/srv/obsidian/vault"
OBSIDIAN_DOMAIN=""
OBSIDIAN_URL_PREFIX="/wiki"
```

## Addon Detaljer

### Obsidian Web

- **Formål**: Synkroniser og server Obsidian vault som website
- **Sync**: Syncthing mellem Windows/Android og Arch server
- **URL**: `http://server/wiki/` eller custom domæne
- **Krav**: Syncthing paring via web UI første gang

### Backblaze B2 Backup

- **Formål**: Automatisk offsite backup
- **Værktøj**: rclone med kryptering
- **Schedule**: Daglig inkrementel backup
- **Krav**: Manuel B2 konfiguration via `rclone config`

### cgit

- **Formål**: Git repository web viewer
- **URL**: `http://server/git/`
- **Integration**: Caddy reverse proxy
- **Krav**: Git repos i `/srv/git/`

## Struktur

```
arch-server-addons/
├── addons/                    # Addon moduler
│   ├── obsidian-web/         # Obsidian website addon
│   ├── backblaze-backup/     # Backup addon
│   └── cgit/                 # Git viewer addon
├── ansible/                  # Ansible playbooks
├── scripts/                  # Deployment scripts
├── config/                   # Konfigurationsfiler
└── docs/                     # Dokumentation
```

## Support

For issues relateret til:
- **Base server**: Åbn issue i [arch-server](https://github.com/humethix/arch-server) repo
- **Addons**: Åbn issue i dette repo

## Licens

MIT License - samme som base-repo.
