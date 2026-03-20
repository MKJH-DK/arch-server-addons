# Arch Server Addons

Udvidelser til [arch-server](https://github.com/humethix/arch-server) base installationen.

## Oversigt

Dette repo indeholder addons til Arch Server base installationen. Addons er designet til at udvide funktionaliteten uden at ændre i base-repoen.

### Tilgængelige Addons

**Services:**

1. **Obsidian Web** - Server Obsidian vault som statisk website med Syncthing sync
2. **Backblaze B2 Backup** - Automatisk offsite backup til Backblaze B2
3. **cgit** - Lightweight git web viewer
4. **Immich** - Self-hosted fotostyring (kræver Docker)
5. **CrowdSec** - Udvidet sikkerhedskonfiguration (oveni base-installationen)
6. **Ollama** - Kør LLMs lokalt på serveren (backend for AI CLI tools)

**AI CLI Tools:**

7. **Claude Code** - Anthropic's AI kodningsassistent (`claude`)
8. **Gemini CLI** - Google's AI kodningsassistent (`gemini`)
9. **ShellGPT** - AI i terminalen via sgpt (`sgpt`)
10. **Codex** - OpenAI's AI kodningsagent (`codex`)

## Forudsætninger

- Arch Server base installation er deployet via `/root/arch/scripts/deploy.sh`
- Ansible er installeret på serveren
- Serveren har internetadgang
- **AI CLI tools**: Node.js 18+ og/eller Python 3.9+ (installeres automatisk)

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
# Aktiver/deaktiver service-addons
OBSIDIAN_ENABLED=true
BACKBLAZE_ENABLED=false
CGIT_ENABLED=false
IMMICH_ENABLED=false
CROWDSEC_ENABLED=false
OLLAMA_ENABLED=false

# Aktiver/deaktiver AI CLI tools
CLAUDE_CLI_ENABLED=false
GEMINI_CLI_ENABLED=false
SHELLGPT_ENABLED=false
CODEX_ENABLED=false

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

### Immich

- **Formål**: Self-hosted foto- og videostyring
- **URL**: `http://server/photos/` eller custom domæne
- **Krav**: Docker og Docker Compose (base installerer Podman - installer Docker separat)

### CrowdSec (udvidet)

- **Formål**: Avanceret sikkerhed med dashboard, backup og Caddy-integration
- **Note**: Base-serveren installerer allerede CrowdSec grundopsætning. Denne addon tilføjer udvidet konfiguration oveni.

### Ollama

- **Formål**: Kør LLMs lokalt - bruges som backend for AI CLI tools eller direkte
- **API**: `http://localhost:11434`
- **Kommandoer**: `ollama pull`, `ollama run`, `ollama-manage status`
- **Modeller**: llama3.1, codellama, mistral, qwen2.5-coder, m.fl.
- **Krav**: Min. 8 GB RAM (anbefalet 16+ GB), GPU valgfrit men anbefalet

### Claude Code

- **Formål**: Anthropic's AI kodningsassistent i terminalen
- **Kommando**: `claude`
- **Installation**: npm (`@anthropic-ai/claude-code`)
- **Krav**: Node.js 18+, `ANTHROPIC_API_KEY` env var

### Gemini CLI

- **Formål**: Google's AI kodningsassistent i terminalen
- **Kommando**: `gemini`
- **Installation**: npm (`@google/gemini-cli`)
- **Krav**: Node.js 18+, `GEMINI_API_KEY` env var

### ShellGPT

- **Formål**: AI-drevet shell-assistent
- **Kommando**: `sgpt`
- **Installation**: pipx (`shell-gpt`)
- **Krav**: Python 3.9+, `OPENAI_API_KEY` env var (understøtter også andre backends via litellm)

### Codex

- **Formål**: OpenAI's AI kodningsagent
- **Kommando**: `codex`
- **Installation**: npm (`@openai/codex`)
- **Krav**: Node.js 18+, `OPENAI_API_KEY` env var

## Struktur

```
arch-server-addons/
├── addons/                    # Addon moduler
│   ├── obsidian-web/         # Obsidian website addon
│   ├── backblaze-backup/     # Backup addon
│   ├── cgit/                 # Git viewer addon
│   ├── immich/               # Fotostyring addon
│   ├── crowdsec/             # Udvidet sikkerhed addon
│   ├── ollama/               # Lokal LLM server
│   ├── claude-cli/           # Claude Code CLI
│   ├── gemini-cli/           # Gemini CLI
│   ├── shellgpt/             # ShellGPT (sgpt)
│   └── codex/                # OpenAI Codex CLI
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
