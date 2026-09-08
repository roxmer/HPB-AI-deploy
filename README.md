# HPB-AI Deployment Toolkit

Scripts and reference data for standing up an HPB-AI instance. This is deliberately kept **separate** from the application source (`11.-HPB`): the app repo stays a clean, generic codebase, and this toolkit is the "how to actually run it" layer, including a default set of lookup-list data. Nothing here is bundled into the application build itself.

## Layout

Expected to sit as a sibling of `11.-HPB` and `ai_agent_learning`:

```
HPB-AI/
├── 11.-HPB/              the application (separate repo)
├── ai_agent_learning/     AI agent tooling (separate repo)
└── deploy_HPB/            this repo
```

- **`deploy_hpb_local.sh`** — clones/updates `11.-HPB`, applies local patches from `ai_agent_learning/backend_patches`, builds and runs the app locally.
- **`imports_fixed.sh`** — once the app is running, seeds its lookup lists (Signs, Symptoms, Risk Factor, Clinical Diagnosis, tumor typing, medicines, etc.) by importing the `.xlsx` files in `HPB_Templates/` through the app's own API.
- **`import.csv`** — maps each lookup list's API path to its template filename; edit this if a list's endpoint or filename changes.
- **`HPB_Templates/`** — the reference lookup-list content itself (coded against ICD-10-SE / ICD-O-3 / ATC / KVÅ where applicable — see `ai_agent_learning/CODE_COLUMN_FEATURE_SUMMARY.md` for how these were built).

## Why lookup lists live here, not in the app

The application's database migrations only create the lookup-list tables — they never insert rows. Seed data is a deployment-time concern, supplied by whoever is standing up an instance, via `imports_fixed.sh` reading `HPB_Templates/`. That keeps the app repo free of any assumption about which lookup-list content a given deployment should ship with: a different deployment can swap in its own `HPB_Templates/` (or point `import.csv` elsewhere) without touching application code.

## Setup

```
cp .env.example .env
# fill in .env: MYSQL_PASSWORD, YOUR_REPO, HPB_ADMIN_USERNAME, HPB_ADMIN_PASSWORD
chmod +x deploy_hpb_local.sh imports_fixed.sh

./deploy_hpb_local.sh              # fresh DB + build + run (Ollama backend, default)
# once the app is up, in another terminal:
./imports_fixed.sh import.csv      # seed the lookup lists
```

See `deploy_hpb_local.sh --help`-style usage comments at the top of the script for backend/DB-mode flags (`--backend claude`, `--keep-db`, `--commit <ref>`).

## What's not in this repo

Personal test-data scripts (synthetic patients, cleanup SQL), older/retired deployment script variants, and the separate server-installation track are kept out of this trimmed toolkit — they remain in the working Dropbox copy of `HPB-AI` and aren't part of what's distributed here.
