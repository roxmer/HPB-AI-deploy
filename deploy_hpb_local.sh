#!/bin/bash

# =============================================================
#   HPB-AI Local Deployment Script — Multi-Backend
#
#   Supports two AI backends:
#     --backend ollama   (default) Local LLM via Ollama — no API key needed.
#                        Use this for patient data that cannot leave KI.
#     --backend claude   Anthropic Claude API — requires ANTHROPIC_API_KEY.
#                        Use this for development/testing on non-patient data.
#
#   Database modes (same as before):
#     (default)          Reset database
#     --keep-db / -k     Keep existing database data
#
#   Usage examples:
#     ./deploy_hpb_local.sh                          ← Ollama, reset DB
#     ./deploy_hpb_local.sh --keep-db               ← Ollama, keep DB
#     ./deploy_hpb_local.sh --backend claude         ← Claude, reset DB
#     ./deploy_hpb_local.sh --backend claude -k      ← Claude, keep DB
#     ./deploy_hpb_local.sh --commit 57a4a086        ← Deploy a specific commit
#                                                       instead of latest (accepts
#                                                       any git ref: full/short SHA,
#                                                       branch, or tag)
#     ./deploy_hpb_local.sh --local-only             ← Skip cloning the programmers'
#                                                       repo and re-applying patches --
#                                                       deploy 11.-HPB exactly as it
#                                                       sits on disk right now. Use
#                                                       this to test local edits
#                                                       (including ones not yet
#                                                       copied into backend_patches/)
#                                                       without them being overwritten.
#                                                       Not combinable with --commit.
#
#   Before running:
#     chmod +x deploy_hpb_local.sh
# =============================================================

# ── CONFIGURATION ─────────────────────────────────────────────
# Paths are resolved relative to this script's own location, so this
# toolkit works for any checkout, not just this machine -- as long as
# 11.-HPB and ai_agent_learning are cloned as siblings of this deploy_HPB
# folder (the same layout this was developed with).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Secrets and per-user settings load from a local .env file if present
# (copy .env.example to .env and fill it in -- .env is gitignored).
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

MYSQL_PASSWORD="${MYSQL_PASSWORD:?Set MYSQL_PASSWORD in deploy_HPB/.env (copy .env.example to get started)}"
DB_NAME="${DB_NAME:-db_hpb}"
PROJECT_DIR="${PROJECT_DIR:-$PARENT_DIR/11.-HPB}"
PROGRAMMERS_REPO="${PROGRAMMERS_REPO:-https://github.com/kiehealth/11.-HPB.git}"
YOUR_REPO="${YOUR_REPO:?Set YOUR_REPO in deploy_HPB/.env to your own fork, e.g. https://github.com/<you>/HPB-AI.git}"
AI_AGENT_DIR="${AI_AGENT_DIR:-$PARENT_DIR/ai_agent_learning}"
MOLECULAR_AGENT_DIR="${MOLECULAR_AGENT_DIR:-$PARENT_DIR/molecular_report_agent}"
MOLECULAR_SIDECAR_PORT="${MOLECULAR_SIDECAR_PORT:-8090}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:14b}"   # change to qwen2.5:32b when on KI GPU servers
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
# ─────────────────────────────────────────────────────────────

set -e

# ── Parse arguments ───────────────────────────────────────────
KEEP_DB=false
BACKEND="ollama"   # default
COMMIT=""          # default: empty = deploy latest (HEAD of default branch)
LOCAL_ONLY=false   # default: false = clone fresh from programmers' repo and
                   # apply the AI Assistant + backend_patches patches on top,
                   # as before. true (--local-only) = skip all of that and
                   # deploy $PROJECT_DIR exactly as it sits on disk right now
                   # -- no clone, no re-patch, nothing merged in from anywhere.
                   # Use this to test local changes (e.g. edits you're making
                   # directly in 11.-HPB, or changes not yet copied into
                   # backend_patches/) without them being overwritten.

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-db|-k)
      KEEP_DB=true
      shift
      ;;
    --backend)
      BACKEND="$2"
      shift 2
      ;;
    --backend=*)
      BACKEND="${1#--backend=}"
      shift
      ;;
    ollama|claude)
      BACKEND="$1"
      shift
      ;;
    --commit)
      COMMIT="$2"
      shift 2
      ;;
    --commit=*)
      COMMIT="${1#--commit=}"
      shift
      ;;
    --local-only)
      LOCAL_ONLY=true
      shift
      ;;
    *)
      echo "❌ Unknown argument: $1"
      echo "   Usage: ./deploy_hpb_local.sh [--backend ollama|claude] [--keep-db|-k] [--commit <sha|branch|tag>] [--local-only]"
      exit 1
      ;;
  esac
done

if [[ "$BACKEND" != "ollama" && "$BACKEND" != "claude" ]]; then
  echo "❌ Invalid backend: $BACKEND. Must be 'ollama' or 'claude'."
  exit 1
fi

if [ "$LOCAL_ONLY" = true ] && [ -n "$COMMIT" ]; then
  echo "❌ --local-only and --commit can't be combined -- --commit checks out a"
  echo "   ref from the programmers' repo, but --local-only skips cloning it."
  exit 1
fi

DB_LABEL="(Reset Database)"
[ "$KEEP_DB" = true ] && DB_LABEL="(Keeping existing database data)"

BACKEND_LABEL="Local LLM via Ollama ($OLLAMA_MODEL)"
AGENT_FILE="api_agent_ollama.py"
AGENT_MODULE="api_agent_ollama"
[ "$BACKEND" = "claude" ] && BACKEND_LABEL="Anthropic Claude API"
[ "$BACKEND" = "claude" ] && AGENT_FILE="api_agent.py"
[ "$BACKEND" = "claude" ] && AGENT_MODULE="api_agent"

echo ""
echo "======================================"
echo "  HPB-AI Local Deployment Starting..."
echo "  Backend    : $BACKEND_LABEL"
if [ "$LOCAL_ONLY" = true ]; then
  echo "  Source     : LOCAL ONLY -- deploying \$PROJECT_DIR as-is, no clone, no patching"
else
  echo "  Commit     : ${COMMIT:-latest (HEAD of default branch)}"
fi
echo "  $DB_LABEL"
echo "======================================"
echo ""

# ── STEP 0: Backend-specific checks ─────────────────────────
echo "▶ Step 0: Checking AI backend..."

if [ "$BACKEND" = "claude" ]; then
  # Re-read API key fresh from .zshrc (same fix as original script)
  if [ -f "$HOME/.zshrc" ]; then
    FRESH_KEY_LINE=$(grep '^export ANTHROPIC_API_KEY=' "$HOME/.zshrc" | tail -1)
    if [ -n "$FRESH_KEY_LINE" ]; then
      eval "$FRESH_KEY_LINE"
      echo "   (Re-read ANTHROPIC_API_KEY fresh from ~/.zshrc)"
    fi
  fi

  if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ ANTHROPIC_API_KEY is not set. Add it to ~/.zshrc and re-run."
    exit 1
  fi
  TRIMMED_KEY=$(echo "$ANTHROPIC_API_KEY" | xargs)
  if [ "$ANTHROPIC_API_KEY" != "$TRIMMED_KEY" ]; then
    echo "⚠️  API key has leading/trailing whitespace — trimming for this session."
    export ANTHROPIC_API_KEY="$TRIMMED_KEY"
  fi
  echo "✅ Anthropic API key is set and clean."

else
  # Ollama: check the server is running and the model is pulled
  curl -s "$OLLAMA_HOST" > /dev/null 2>&1 || {
    echo "❌ Ollama is not running. Open the Ollama app from your Applications folder,"
    echo "   wait for the menu bar icon to appear, then re-run this script."
    exit 1
  }
  echo "✅ Ollama server is running."

  # Check the model is available locally
  MODEL_EXISTS=$(curl -s "$OLLAMA_HOST/api/tags" | python3 -c \
    "import sys,json; tags=json.load(sys.stdin); \
     print('yes' if any('$OLLAMA_MODEL' in m['name'] for m in tags.get('models',[])) else 'no')" \
    2>/dev/null || echo "unknown")

  if [ "$MODEL_EXISTS" = "no" ]; then
    echo "⚠️  Model '$OLLAMA_MODEL' is not pulled yet. Pulling now..."
    echo "   (This downloads ~9GB — may take several minutes)"
    ollama pull "$OLLAMA_MODEL"
    echo "✅ Model pulled successfully."
  elif [ "$MODEL_EXISTS" = "yes" ]; then
    echo "✅ Model '$OLLAMA_MODEL' is available."
  else
    echo "⚠️  Could not verify model — continuing anyway."
  fi
fi

# ── STEP 1: Set Java 21 ──────────────────────────────────────
echo ""
echo "▶ Step 1: Setting Java 21..."
export JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null) || {
  echo "❌ Java 21 not found. Install with: brew install openjdk@21"
  exit 1
}
export PATH=$JAVA_HOME/bin:$PATH
echo "✅ Java version: $(java -version 2>&1 | head -1)"

# ── STEP 2: Check Maven ──────────────────────────────────────
echo ""
echo "▶ Step 2: Checking Maven..."
mvn -version > /dev/null 2>&1 || {
  echo "❌ Maven not found. Install with: brew install maven"
  exit 1
}
echo "✅ Maven is available."

# ── STEP 3: Clone programmers' repo fresh (skipped in --local-only) ──
echo ""
if [ "$LOCAL_ONLY" = true ]; then
  echo "▶ Step 3: Skipped (--local-only) -- deploying $PROJECT_DIR as-is."
  if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ --local-only requires $PROJECT_DIR to already exist -- there's nothing"
    echo "   to deploy. Run without --local-only at least once first, or point"
    echo "   PROJECT_DIR at an existing checkout in deploy_HPB/.env."
    exit 1
  fi
  cd "$PROJECT_DIR"
  if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "   Deployed commit : $(git rev-parse --short HEAD 2>/dev/null)  — $(git log -1 --format='%s' 2>/dev/null) (+ uncommitted local changes, if any)"
  fi
else
  if [ -n "$COMMIT" ]; then
    echo "▶ Step 3: Cloning programmers' repo and checking out commit $COMMIT..."
  else
    echo "▶ Step 3: Cloning latest code from programmers' repo..."
  fi
  if [ -d "$PROJECT_DIR" ]; then
    echo "   Removing existing folder..."
    rm -rf "$PROJECT_DIR"
  fi
  cd "$PARENT_DIR"
  git clone "$PROGRAMMERS_REPO"
  echo "✅ Programmers' repo cloned successfully."

  cd "$PROJECT_DIR"
  if [ -n "$COMMIT" ]; then
    git checkout "$COMMIT" || {
      echo "❌ Could not check out commit/ref '$COMMIT' — is it pushed to $PROGRAMMERS_REPO?"
      exit 1
    }
  fi
  echo "   Deployed commit : $(git rev-parse --short HEAD)  — $(git log -1 --format='%s')"
fi

NAVUTIL="$PROJECT_DIR/src/main/resources/static/js/util/NavUtil.js"

# ── STEP 4: Regenerate Maven wrapper ────────────────────────
echo ""
echo "▶ Step 4: Regenerating Maven wrapper..."
cd "$PROJECT_DIR"
mvn -N io.takari:maven:wrapper > /dev/null 2>&1
echo "✅ Maven wrapper regenerated."

# ── STEP 5: Apply AI Assistant files (skipped in --local-only) ──
if [ "$LOCAL_ONLY" = false ]; then
echo ""
echo "▶ Step 5: Applying AI Assistant files..."

cp "$AI_AGENT_DIR/ai-assistant.html" \
   "$PROJECT_DIR/src/main/resources/static/ai-assistant.html"
echo "   ✅ ai-assistant.html copied"

mkdir -p "$PROJECT_DIR/src/main/resources/static/js/view"
cp "$AI_AGENT_DIR/AiAssistantView.js" \
   "$PROJECT_DIR/src/main/resources/static/js/view/AiAssistantView.js"
echo "   ✅ AiAssistantView.js copied"

python3 - "$NAVUTIL" << 'PYEOF'
import sys

navutil_path = sys.argv[1]

with open(navutil_path, "r") as f:
    content = f.read()

changed = False

menu_entry = "{id: 'AiAssistant', icon: 'fas fa-robot', title: 'AI Assistant', authority: 'AI_ASSISTANT', page: 'ai-assistant.html'},"

if "id: 'AiAssistant'" not in content:
    anchor = "{id: 'Patient', icon: 'fas fa-user-injured', title: 'Patient', authority: 'PATIENT', page: 'patient.html'},"
    if anchor not in content:
        print("   ❌ ERROR: Could not find anchor line for menu entry in NavUtil.js")
        sys.exit(1)
    content = content.replace(anchor, anchor + "\n        " + menu_entry, 1)
    changed = True
    print("   ✅ Menu entry added to mainItems")
else:
    print("   ℹ️  Menu entry already present — skipping (idempotent)")

if "AI Assistant forced visible" not in content:
    target = "static showFullNavigation() {"
    if target not in content:
        print("   ❌ ERROR: Could not find showFullNavigation() in NavUtil.js")
        sys.exit(1)

    import re
    method_match = re.search(r"static showFullNavigation\(\)\s*\{(.*?)\n\s*\}", content, re.DOTALL)
    if not method_match:
        print("   ❌ ERROR: Could not parse showFullNavigation() body")
        sys.exit(1)

    body = method_match.group(1)
    ai_block = """
        // Always show AI Assistant regardless of authority
        const aiContainer = document.querySelector('#linkAiAssistantContainer');
        const aiLink      = document.querySelector('#linkAiAssistant');
        if (aiContainer && aiLink) {
            aiContainer.hidden = false;
            aiLink.href = `${EndPoints.BASE_URL}/ai-assistant.html`;
            console.log("AI Assistant forced visible");
        }"""

    new_body = body + ai_block
    content = content.replace(
        "static showFullNavigation() {" + body + "\n    }",
        "static showFullNavigation() {" + new_body + "\n    }",
        1
    )
    changed = True
    print("   ✅ Force-show block added to showFullNavigation()")
else:
    print("   ℹ️  Force-show block already present — skipping (idempotent)")

if changed:
    with open(navutil_path, "w") as f:
        f.write(content)

with open(navutil_path, "r") as f:
    final_content = f.read()

ok = True
if "id: 'AiAssistant'" not in final_content:
    print("   ❌ VERIFICATION FAILED: menu entry missing after patch")
    ok = False
if "AI Assistant forced visible" not in final_content:
    print("   ❌ VERIFICATION FAILED: force-show block missing after patch")
    ok = False

count = final_content.count("id: 'AiAssistant'")
if count > 1:
    print(f"   ❌ VERIFICATION FAILED: {count} duplicate AiAssistant entries found!")
    ok = False

if not ok:
    sys.exit(1)

print("   ✅ Verification passed — NavUtil.js correctly patched")
PYEOF

if [ $? -ne 0 ]; then
    echo "❌ NavUtil.js patching failed."
    exit 1
fi

SECURITY_CONFIG=$(find "$PROJECT_DIR/src/main/java" -name "SecurityConfig.java" | head -1)
if [ -n "$SECURITY_CONFIG" ]; then
    if grep -q "/ai-assistant.html" "$SECURITY_CONFIG"; then
        echo "   ℹ️  SecurityConfig.java already permits /ai-assistant.html — skipping"
    else
        sed -i '' 's|"/user_profile.html",|"/user_profile.html", "/ai-assistant.html",|' "$SECURITY_CONFIG"
        if grep -q "/ai-assistant.html" "$SECURITY_CONFIG"; then
            echo "   ✅ SecurityConfig.java updated"
        else
            echo "   ❌ ERROR: Could not patch SecurityConfig.java"
            exit 1
        fi
    fi
else
    echo "   ❌ ERROR: SecurityConfig.java not found"
    exit 1
fi

echo "✅ All AI Assistant files applied and verified."
else
  echo ""
  echo "▶ Step 5: Skipped (--local-only)."
fi

# ── STEP 5b: Apply backend bug-fix patches (TEMPORARY) ───────
if [ "$LOCAL_ONLY" = false ]; then
#   These 4 files fix two real bugs in the programmers' repo:
#     1. TechniqueServiceImpl.importAllData() checked Test Result /
#        Test Unit uniqueness globally (testResultRepo.findByName,
#        testUnitRepo.findByUnit) instead of scoped per Test Name,
#        so reused labels like "Normal"/"Elevated"/"mg/dL" silently
#        skipped every test after the first one to use them. Also
#        made the Test Names import defensive so a missing Technique
#        match skips that row instead of crashing the whole import
#        with a Hibernate not-null exception.
#     2. TestResultView.js's "+Test Result" button read a stale
#        localStorage value set by the last Test Name flask-icon
#        click, so adding a result while viewing a different test
#        (via the filter dropdown) silently saved it against the
#        wrong Test Name.
#     3. TestResultServiceImpl.get() / TestUnitServiceImpl.get() had a
#        leftover pageSize<=0 shortcut branch calling the old
#        repo.search(searchTerm, pageable) method, which no longer
#        exists now that TestResultRepo/TestUnitRepo were patched to
#        searchTestResults/searchTestUnits(testNameIds, searchTerm,
#        pageable) -- this alone was a compile-breaking error, not
#        just a runtime bug. TechniqueService also never declared
#        getForDropdown() even though TechniqueServiceImpl implements
#        it with @Override -- another compile error. (2026-07-22)
#   Source of truth for these patches: $AI_AGENT_DIR/backend_patches/
#   (mirrors the exact repo-relative paths). Remove this step once
#   the programmers have merged the fix into kiehealth/11.-HPB.
#
#   IMPORTANT: any time you hand-fix a compile/runtime error directly
#   in $PROJECT_DIR, it WILL be silently lost on the next redeploy --
#   Step 3 above does `rm -rf $PROJECT_DIR` and re-clones fresh from
#   the programmers' repo before this step runs. Always copy the
#   fixed file into backend_patches/ (same repo-relative path) too,
#   or the fix has to be redone from scratch every time.
echo ""
echo "▶ Step 5b: Applying backend bug-fix patches (temporary, pending upstream merge)..."

BACKEND_PATCHES_DIR="$AI_AGENT_DIR/backend_patches"

if [ -d "$BACKEND_PATCHES_DIR" ]; then
    PATCH_COUNT=0
    while IFS= read -r -d '' patch_file; do
        rel_path="${patch_file#$BACKEND_PATCHES_DIR/}"
        target_path="$PROJECT_DIR/$rel_path"
        mkdir -p "$(dirname "$target_path")"
        cp "$patch_file" "$target_path"
        echo "   ✅ $rel_path"
        PATCH_COUNT=$((PATCH_COUNT + 1))
    done < <(find "$BACKEND_PATCHES_DIR" -type f -print0)
    echo "✅ Applied $PATCH_COUNT backend patch file(s)."
else
    echo "   ℹ️  No backend_patches folder found — skipping (nothing to apply)."
fi
else
  echo ""
  echo "▶ Step 5b: Skipped (--local-only)."
fi

# ── STEP 6: Update application.properties ───────────────────
echo ""
echo "▶ Step 6: Updating database password in application.properties..."
PROPS_FILE="$PROJECT_DIR/src/main/resources/application.properties"
sed -i '' "s|^spring.datasource.password=.*|spring.datasource.password=$MYSQL_PASSWORD|" "$PROPS_FILE"

# When --keep-db is used, the freshly-cloned 11.-HPB code can contain new
# Flyway migrations that were added upstream AFTER your local database's
# migration history was last recorded. Flyway's default strict validation
# then refuses to start ("Detected resolved migration not applied to
# database: X"). Since this is a local test DB (not production) and new
# migrations here are simple additive changes (new tables/columns), it's
# safe to let Flyway apply them out of order instead of failing the boot.
if ! grep -q "^spring.flyway.out-of-order=" "$PROPS_FILE"; then
  # Ensure the file ends with a newline first -- otherwise the appended
  # line gets glued onto the end of the last existing line.
  [ -n "$(tail -c1 "$PROPS_FILE")" ] && echo "" >> "$PROPS_FILE"
  echo "spring.flyway.out-of-order=true" >> "$PROPS_FILE"
fi
echo "✅ application.properties updated."

# ── STEP 7: Push merged result to your HPB-AI repo ──────────
echo ""
echo "▶ Step 7: Pushing merged result to your HPB-AI repo..."
cd "$PROJECT_DIR"
git remote add origin "$YOUR_REPO" 2>/dev/null || git remote set-url origin "$YOUR_REPO"
git add .
COMMIT_MSG="Auto-deploy: merge programmers + AI Assistant [backend: $BACKEND] $(date '+%Y-%m-%d %H:%M')"
[ "$LOCAL_ONLY" = true ] && COMMIT_MSG="Auto-deploy: local-only snapshot [backend: $BACKEND] $(date '+%Y-%m-%d %H:%M')"
git commit -m "$COMMIT_MSG" --no-edit || echo "   (Nothing new to commit)"
git push origin main --force
echo "✅ Pushed to HPB-AI repo."

# ── STEP 8: Start MySQL ──────────────────────────────────────
echo ""
echo "▶ Step 8: Checking MySQL..."
mysql -u root -p"$MYSQL_PASSWORD" --protocol=TCP -e "SELECT 1;" > /dev/null 2>&1 || {
  echo "❌ Could not connect to MySQL. Is it running? Check System Preferences → MySQL."
  exit 1
}
echo "✅ MySQL is running."

# ── STEP 9: Reset OR keep database ──────────────────────────
echo ""
if [ "$KEEP_DB" = true ]; then
  echo "▶ Step 9: Checking database (keep-db mode)..."
  DB_EXISTS=$(mysql -u root -p"$MYSQL_PASSWORD" --protocol=TCP -e "SHOW DATABASES LIKE '$DB_NAME';" 2>/dev/null | grep "$DB_NAME" || true)
  if [ -z "$DB_EXISTS" ]; then
    echo "   Database '$DB_NAME' not found — creating it..."
    mysql -u root -p"$MYSQL_PASSWORD" --protocol=TCP -e "CREATE DATABASE $DB_NAME;"
    echo "✅ Database '$DB_NAME' created."
  else
    echo "✅ Database '$DB_NAME' exists — keeping existing data."
  fi

  echo ""
  echo "▶ Step 9b: Running Flyway repair..."
  cd "$PROJECT_DIR"
  mvn flyway:repair \
    -Dflyway.url=jdbc:mysql://localhost:3306/$DB_NAME \
    -Dflyway.user=root \
    -Dflyway.password="$MYSQL_PASSWORD" 2>/dev/null || echo "   (Flyway repair not needed, continuing...)"
  echo "✅ Flyway repair done."
else
  echo "▶ Step 9: Resetting database..."
  mysql -u root -p"$MYSQL_PASSWORD" --protocol=TCP -e "DROP DATABASE IF EXISTS $DB_NAME; CREATE DATABASE $DB_NAME;"
  echo "✅ Database '$DB_NAME' recreated."
fi

# ── STEP 10: Build ────────────────────────────────────────────
echo ""
echo "▶ Step 10: Running Maven clean install..."
cd "$PROJECT_DIR"
mvn clean install -DskipTests
echo "✅ Build successful."

# ── STEP 11: Clear ports ──────────────────────────────────────
echo ""
echo "▶ Step 11: Clearing ports 8000, $MOLECULAR_SIDECAR_PORT and 9080 if in use..."
lsof -ti:8000 | xargs kill -9 2>/dev/null || true
lsof -ti:"$MOLECULAR_SIDECAR_PORT" | xargs kill -9 2>/dev/null || true
lsof -ti:9080 | xargs kill -9 2>/dev/null || true
sleep 1
echo "✅ Ports cleared."

# ── STEP 12: Start AI Agent ───────────────────────────────────
echo ""
echo "▶ Step 12: Starting Python AI Agent ($BACKEND_LABEL) on port 8000..."
cd "$AI_AGENT_DIR"

# Activate the project's venv (this is where uvicorn/fastapi/ollama/
# mysql-connector-python actually live -- see Section 1.2 of the
# deployment guide). Previously this activated a conda env called
# "ai_agent" instead, left over from before the project switched to a
# venv; that env never had these packages installed, so uvicorn could
# not be found ("nohup: uvicorn: No such file or directory" in agent.log).
source "$AI_AGENT_DIR/.venv/bin/activate"

if [ "$BACKEND" = "claude" ]; then
  env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
      nohup uvicorn "$AGENT_MODULE:app" --host 0.0.0.0 --port 8000 \
      > "$AI_AGENT_DIR/agent.log" 2>&1 &
else
  nohup uvicorn "$AGENT_MODULE:app" --host 0.0.0.0 --port 8000 \
      > "$AI_AGENT_DIR/agent.log" 2>&1 &
fi

AI_PID=$!
echo "✅ AI Agent started (PID: $AI_PID). Logs: $AI_AGENT_DIR/agent.log"
sleep 4

curl -s http://localhost:8000/health > /dev/null 2>&1 \
  && echo "✅ AI Agent health check passed." \
  || echo "⚠️  AI Agent did not respond yet — check agent.log if issues arise"

# ── STEP 12b: Start molecular report parsing sidecar ──────────
#   Wraps molecular_report_agent/extract_molecular_report.py's parse_report() in a tiny
#   localhost-only HTTP service, so the Add Analysis "Automatic" mode can parse an
#   uploaded PDF via the Java backend (POST /api/analysis/parse_preview) without
#   reimplementing the parser in Java. See molecular_report_agent/PLAN_AUTOMATIC_MODE.md.
#   Lives as a sibling of this deploy_HPB folder, same as ai_agent_learning -- Step 3's
#   `rm -rf $PROJECT_DIR` never touches it, so nothing here needs re-patching on redeploy.
echo ""
echo "▶ Step 12b: Starting molecular report parsing sidecar on port $MOLECULAR_SIDECAR_PORT..."
pip3 install --user --quiet -r "$MOLECULAR_AGENT_DIR/requirements.txt"
cd "$MOLECULAR_AGENT_DIR"
nohup python3 service.py --port "$MOLECULAR_SIDECAR_PORT" \
    > "$MOLECULAR_AGENT_DIR/sidecar.log" 2>&1 &
SIDECAR_PID=$!
echo "✅ Report parsing sidecar started (PID: $SIDECAR_PID). Logs: $MOLECULAR_AGENT_DIR/sidecar.log"
sleep 2

curl -s "http://localhost:$MOLECULAR_SIDECAR_PORT/health" > /dev/null 2>&1 \
  && echo "✅ Report parsing sidecar health check passed." \
  || echo "⚠️  Report parsing sidecar did not respond yet — check sidecar.log if Automatic-mode parsing fails"

# ── STEP 13: Start SpringBoot ─────────────────────────────────
echo ""
echo "======================================"
echo "  HPB Application Running"
echo "  Backend    : $BACKEND_LABEL"
echo "  Mode       : $DB_LABEL"
echo "  SpringBoot : http://localhost:9080"
echo "  AI Agent   : http://localhost:8000"
echo "  AI Docs    : http://localhost:8000/docs"
echo "  Agent Log  : $AI_AGENT_DIR/agent.log"
echo "  Sidecar    : http://localhost:$MOLECULAR_SIDECAR_PORT (Automatic-mode PDF parsing -- Java backend only, not browser-facing)"
echo "  Sidecar Log: $MOLECULAR_AGENT_DIR/sidecar.log"
echo "======================================"
echo ""
cd "$PROJECT_DIR"
mvn spring-boot:run -DskipTests
