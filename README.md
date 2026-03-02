---
title: OpenClaw CS Assistant
emoji: 🧠
colorFrom: indigo
colorTo: cyan
sdk: docker
app_port: 7860
pinned: false
---

# OpenClaw CS Assistant

AI-powered research and productivity assistant for Computer Science students,
running on **Hugging Face Spaces** (free CPU Basic tier).

Built on [OpenClaw](https://openclaw.ai/) with **Google Gemini 2.5 Flash** as
the primary model.

## What It Does

| Capability | How |
|------------|-----|
| **Web Research** | Headless Chromium via Playwright — browse any site, JS-heavy or paywalled |
| **Document Generation** | Markdown reports, academic summaries, formatted docs |
| **Presentations** | Slide decks from prompts or outlines (SlideSPeak skill) |
| **YouTube** | Fetch transcripts, search videos for lecture material |
| **Math & Code** | LaTeX equations, clean code in Python / JS / C++ / Java |
| **GitHub** | Create issues, review PRs, check CI runs |
| **Autonomous Tasks** | Morning assignment summaries via HEARTBEAT schedule |

---

## Quick Deploy

### 1. Fork & Create Space

1. **Fork** this repository on GitHub
2. Go to [huggingface.co/new-space](https://huggingface.co/new-space)
3. Choose **Docker** as the SDK
4. Link your forked GitHub repo (or push directly to the Space repo)

### 2. Add Secrets

In **Space Settings → Repository secrets**, add:

| Secret | Required | Description |
|--------|----------|-------------|
| `GOOGLE_API_KEY` | **Yes** | Google AI Studio key — [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |
| `OPENCLAW_GATEWAY_TOKEN` | **Yes** | Any strong random string — protects the web dashboard |
| `TELEGRAM_BOT_TOKEN` | No | Enables the Telegram channel ([@BotFather](https://t.me/BotFather)) |
| `GH_TOKEN` | No | Enables the GitHub skill (issues, PRs, CI) |
| `BRAVE_API_KEY` | No | Enables Brave web search for the Daily Tech Brief |
| `STORAGE_MODE` | No | Set to `supabase` for persistent storage (default: `local`) |
| `SUPABASE_URL` | No* | Supabase project URL (required if `STORAGE_MODE=supabase`) |
| `SUPABASE_ANON_KEY` | No* | Supabase anon key (required if `STORAGE_MODE=supabase`) |
| `SUPABASE_SERVICE_ROLE_KEY` | No* | Supabase service role key (required if `STORAGE_MODE=supabase`) |
| `SUPABASE_STORAGE_BUCKET` | No | Supabase storage bucket name (default: `openclaw-workspace`) |

> **Tip:** Generate a gateway token quickly:
> `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`

See [.env.example](.env.example) for the full reference.

### 3. Deploy

The Space auto-builds and starts. Once the build finishes, open your Space URL
to access the OpenClaw dashboard on port **7860**.

### 4. (Optional) Pair Telegram

If you set `TELEGRAM_BOT_TOKEN`, open Telegram, find your bot, and send
`/start` to complete pairing.

---

## Project Structure

```
.
├── Dockerfile              ← HF Spaces Docker build
├── entrypoint.sh           ← Startup: seed config, install skills, launch gateway
├── .env.example            ← Environment variable reference
├── .dockerignore
├── config/
│   ├── openclaw.json       ← Gateway, model, auth, skills, logging config
│   ├── SOUL.md             ← Agent persona & formatting rules
│   ├── HEARTBEAT.md        ← Autonomous scheduled tasks
│   ├── security-rules.md   ← Security guardrails (injected into system prompt)
│   └── skills-manifest.txt ← ClawHub skills auto-installed on startup
├── workspace-templates/    ← Seeded into workspace on first boot
├── scripts/
│   ├── validate-config.sh  ← JSON lint + no-raw-keys check
│   └── check-secrets.sh    ← Scans tracked files for leaked secrets
└── .githooks/
    └── pre-commit          ← Runs validation + secret scan before commit
```

---

## Configuration Reference

### `config/openclaw.json`

| Key | Value | Notes |
|-----|-------|-------|
| `gateway.port` | `7860` | HF Spaces requirement |
| `gateway.token` | `${OPENCLAW_GATEWAY_TOKEN}` | Set in Space secrets |
| `agents.defaults.model.primary` | `google/gemini-2.5-flash` | Free-tier friendly |
| `skills.shell.enabled` | `false` | **Disabled** for security |
| `skills.playwright.enabled` | `true` | Headless Chromium browsing |
| `skills.fs.enabled` | `true` | Sandboxed to `/app/data/workspace` |
| `skills.slidespeak.enabled` | `true` | Presentation generation |
| `auth.profiles.google:studio` | `provider: google, mode: token` | Uses `GOOGLE_API_KEY` |
| `storage.mode` | `${STORAGE_MODE:-local}` | `local` or `supabase` |
| `storage.supabase.*` | env var refs | Only used when `STORAGE_MODE=supabase` |

### `config/SOUL.md`

Defines the agent's persona: peer-like CS study partner. LaTeX for all math,
clean modular code, structured Markdown output.

### `config/HEARTBEAT.md`

| Task | Schedule | Description |
|------|----------|-------------|
| Assignment Digest | `0 8 * * *` (08:00 UTC daily) | Scans `Assignments/` for new PDFs, summarizes each |
| Tech Brief | `30 8 * * 1-5` (08:30 UTC weekdays) | Top 3 CS/tech headlines (requires `BRAVE_API_KEY`) |

### `config/skills-manifest.txt`

ClawHub skills auto-installed on container startup:

| Skill | Use Case |
|-------|----------|
| `yt` | YouTube transcript fetching, video search |
| `agent-browser` | Headless browser for JS-heavy / paywalled pages |
| `conventional-commits` | Standardized commit message formatting |
| `github` | GitHub issues, PRs, CI via `gh` CLI |

Add more from [clawhub.ai](https://clawhub.ai/) — one name per line.

---

## Environment Variables

All sensitive values are injected via environment variables — **never hardcoded**.

| Variable | Default | Set In |
|----------|---------|--------|
| `GOOGLE_API_KEY` | — | HF Space secret |
| `OPENCLAW_GATEWAY_TOKEN` | — | HF Space secret |
| `OPENCLAW_GATEWAY_PORT` | `7860` | Dockerfile |
| `OPENCLAW_HOME` | `/app/data` | Dockerfile |
| `TELEGRAM_BOT_TOKEN` | — | HF Space secret (optional) |
| `GH_TOKEN` | — | HF Space secret (optional) |
| `BRAVE_API_KEY` | — | HF Space secret (optional) |
| `STORAGE_MODE` | `local` | HF Space secret (optional) |
| `SUPABASE_URL` | — | HF Space secret (optional) |
| `SUPABASE_ANON_KEY` | — | HF Space secret (optional) |
| `SUPABASE_SERVICE_ROLE_KEY` | — | HF Space secret (optional) |
| `SUPABASE_STORAGE_BUCKET` | `openclaw-workspace` | HF Space secret (optional) |
| `CHROMIUM_PATH` | `/usr/bin/chromium` | Dockerfile |
| `BROWSER_FLAGS` | `--no-sandbox ...` | Dockerfile |

---

## Security

- **Non-root execution** — container runs as `node` (UID 1000)
- **Shell disabled** — `skills.shell.enabled: false` in config
- **API keys via env only** — no secrets in code or config files
- **Chromium sandboxing** — `--no-sandbox` is safe inside container isolation
- **Security rules** — `config/security-rules.md` is injected into the system
  prompt (prompt-injection defense, secret protection, side-effect confirmation)
- **FS sandboxed** — file operations restricted to `/app/data/workspace`
- **Pre-commit hook** — validates config and scans for leaked secrets

---

## Persistent Storage with Supabase (Optional)

HF Spaces containers are **ephemeral** — local files and conversation history
are lost on every restart. To persist data, connect a free
[Supabase](https://supabase.com/) project.

### What Gets Persisted

| Data | Storage Type | Supabase Feature |
|------|-------------|------------------|
| Conversations & chat history | Database rows | PostgreSQL |
| Agent memory & state | Database rows | PostgreSQL |
| Workspace files (docs, PDFs, summaries) | Object storage | Supabase Storage |

### Setup

1. **Create a free Supabase project** at [supabase.com/dashboard](https://supabase.com/dashboard)
2. **Copy your credentials** from **Project Settings → API**:
   - Project URL (e.g. `https://xyzcompany.supabase.co`)
   - `anon` public key
   - `service_role` secret key
3. **Create a storage bucket** named `openclaw-workspace`:
   - Go to **Storage** in the Supabase dashboard
   - Click **New bucket** → name it `openclaw-workspace` → set it **private**
4. **Add secrets** to your HF Space (Settings → Repository secrets):
   ```
   STORAGE_MODE=supabase
   SUPABASE_URL=https://xyzcompany.supabase.co
   SUPABASE_ANON_KEY=eyJhbGciOi...
   SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...
   SUPABASE_STORAGE_BUCKET=openclaw-workspace
   ```
5. **Restart** the Space — the entrypoint will confirm Supabase is active in logs

### Disable

Remove `STORAGE_MODE` (or set it to `local`) and restart. The agent will fall
back to ephemeral local storage.

### Cost

Supabase's free tier includes 500 MB database + 1 GB storage — more than enough
for a personal agent.

---

## Customization

### Change the model

Edit `config/openclaw.json` → `agents.defaults.model.primary`:

```json
"primary": "google/gemini-2.5-pro"
```

### Add a ClawHub skill

Edit `config/skills-manifest.txt`, add the skill name, commit & push.

### Add a custom skill

Create a directory under `workspace-templates/skills/my-skill/` with a
`skill.json` manifest and handler scripts. They'll be seeded into the workspace
on first boot.

### Switch to Anthropic Claude

1. Change `agents.defaults.model.primary` to `anthropic/claude-sonnet-4-20250514`
2. Update `auth` section: provider `anthropic`, mode `token`
3. Add `ANTHROPIC_API_KEY` as a Space secret

---

## Development

### Enable pre-commit hook

```bash
git config core.hooksPath .githooks
```

### Validate config locally

```bash
bash scripts/validate-config.sh
bash scripts/check-secrets.sh
```

### Build & test locally

```bash
docker build -t openclaw-cs .
docker run --rm -p 7860:7860 \
  -e GOOGLE_API_KEY=your-key \
  -e OPENCLAW_GATEWAY_TOKEN=your-token \
  openclaw-cs
```

Then open `http://localhost:7860`.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Space shows "Building" forever | Check build logs; ensure `GOOGLE_API_KEY` is set |
| "Permission denied" errors | Verify `chown node:node` in Dockerfile covers all data dirs |
| Chromium crashes | Confirm `BROWSER_FLAGS` includes `--no-sandbox --disable-dev-shm-usage` |
| Skills not installing | Check network access; ClawHub registry must be reachable |
| Gateway not accessible | Ensure port is `7860` in both config and Dockerfile |

---

## License

[MIT](LICENSE)
