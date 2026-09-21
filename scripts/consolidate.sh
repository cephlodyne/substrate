#!/bin/bash
# Used to consolidate a codebase into an LLM-optimized single XML file.
# Automatically filters out binary files, previous runs, and common massive directories.

# --- Configuration & Defaults ---
OUTPUT_FILE="files-consolidated.xml"
TARGET_DIRS=()
SIZE_WARNING_THRESHOLD=500000 # ~125k-150k LLM tokens
MAX_SINGLE_FILE_SIZE=256000   # 250KB limit per file to prevent rogue massive text files (like CSVs or unminified bundles)

# Standard directories to always ignore
EXCLUDE_DIRS=("node_modules" "dist" "build" "public" "vendor" "bin" "__pycache__" "venv" ".venv" ".next" "out" ".git" ".idea" ".vscode" ".terraform" ".local")

# Specific token-heavy, generated, OR SENSITIVE files
EXCLUDE_FILES=(
  "go.sum" "package-lock.json" "yarn.lock" "pnpm-lock.yaml" "poetry.lock"
  "*.tfstate" "*.tfstate.backup" "*.min.js" "*.min.css" "*.map" ".DS_Store"
  ".terraform.lock.hcl" ".terraform.lock.hcl*"
  "*.pem" "*.key" "*.crt" "*.cer" "*.p12" "*.pfx" "id_rsa*" ".env*" "secrets.*"
  "*.sqlite" "*.sqlite3" "*.db" "*.log"
)

# --- Parse Arguments ---
while [[ "$#" -gt 0 ]]; do
  case $1 in
  --output | -o)
    OUTPUT_FILE="$2"
    shift 2
    ;;
  -*)
    echo "Unknown parameter passed: $1"
    exit 1
    ;;
  *)
    TARGET_DIRS+=("$1")
    shift
    ;;
  esac
done

if [ -z "$OUTPUT_FILE" ]; then
  OUTPUT_FILE="files-consolidated.xml"
fi
EXCLUDE_FILES+=("$(basename "$OUTPUT_FILE")")

if [ ${#TARGET_DIRS[@]} -gt 0 ]; then
  SEARCH_BASE=("${TARGET_DIRS[@]}")
else
  SEARCH_BASE=(".")
fi

echo "📝 Output intended for: $OUTPUT_FILE"
FILES=()

# --- Execute File Discovery ---
if git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "🐙 Git repository detected. Using git to resolve files..."

  while IFS= read -r -d '' file_path; do
    [ -f "$file_path" ] || continue

    skip=false

    for ex_dir in "${EXCLUDE_DIRS[@]}"; do
      if [[ "/$file_path/" == *"/$ex_dir/"* ]]; then
        skip=true
        break
      fi
    done

    if ! $skip; then
      basename_file=$(basename "$file_path")
      for ex in "${EXCLUDE_FILES[@]}"; do
        case "$basename_file" in
        $ex)
          skip=true
          break
          ;;
        esac
      done
    fi

    $skip && continue

    # Skip files that are unexpectedly massive
    actual_size=$(wc -c <"$file_path" 2>/dev/null)
    if [ "$actual_size" -gt "$MAX_SINGLE_FILE_SIZE" ]; then
      continue
    fi

    if head -n 1 "$file_path" 2>/dev/null | grep -q "<!-- @GENERATED_CONSOLIDATED_PAYLOAD -->"; then
      continue
    fi

    if ! file -b --mime-encoding "$file_path" | grep -q "binary"; then
      FILES+=("$file_path")
    fi
  done < <(git ls-files -z --cached --others --exclude-standard -- "${SEARCH_BASE[@]}" 2>/dev/null)

else
  echo "📁 No Git repository detected. Falling back to standard find..."

  PRUNE_LOGIC=()
  for dir in "${EXCLUDE_DIRS[@]}"; do
    PRUNE_LOGIC+=("-type" "d" "-name" "$dir" "-prune" "-o")
  done
  for file in "${EXCLUDE_FILES[@]}"; do
    PRUNE_LOGIC+=("-name" "$file" "-prune" "-o")
  done

  while IFS= read -r -d '' file_path; do
    actual_size=$(wc -c <"$file_path" 2>/dev/null)
    if [ "$actual_size" -gt "$MAX_SINGLE_FILE_SIZE" ]; then
      continue
    fi

    if head -n 1 "$file_path" 2>/dev/null | grep -q "<!-- @GENERATED_CONSOLIDATED_PAYLOAD -->"; then
      continue
    fi

    if ! file -b --mime-encoding "$file_path" | grep -q "binary"; then
      FILES+=("$file_path")
    fi
  done < <(find "${SEARCH_BASE[@]}" "${PRUNE_LOGIC[@]}" -type f -print0 2>/dev/null)
fi

FILE_COUNT=${#FILES[@]}

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "⚠️ No text files found matching the criteria."
  exit 0
fi

echo "📦 Compiling $FILE_COUNT text file(s) into LLM context format..."

# --- Write LLM Optimized Output to Temp File ---
TEMP_FILE=$(mktemp)

cat <<'EOF' >"$TEMP_FILE"
<!-- @GENERATED_CONSOLIDATED_PAYLOAD -->
<repository_context>
  <system_instructions>
    You are an expert software architect. Review the 'directory_structure' to understand the project architecture, then review the code in the 'files' section.
    
    YOUR CORE GOAL: Write code that a human can easily read, troubleshoot, and develop further. Do not write complex "LLM-only" code.

    CRITICAL ARCHITECTURE & STYLE RULES:
    1. STRICT SECURITY STANDARDS: Assume a highly secure environment. Code must comply with strict Content Security Policies (CSP) and CORS policies. NEVER use inline styles, inline scripts, `eval()`, or unsafe DOM manipulation (e.g., raw innerHTML). Always validate and sanitize inputs to prevent injection attacks.
    2. FEATURE-DRIVEN ORGANIZATION: Group code by function/feature, not by technical type. Co-locate the components, data logic, and utilities for a specific feature together.
    3. BALANCED MODULARITY: Keep logic isolated and DRY, but do not fragment the codebase into overly tiny, brittle files. Group highly cohesive logic together.
    4. HUMAN READABILITY FIRST: Write simple, flat code. Avoid deep nesting (use early returns). Avoid clever, unreadable one-liners. 
    5. SURFACE CONFIGURATION: Extract tweakable parameters, constants, and magic strings to the top of the file or a clear config block. Do not bury them.
    6. EXPLICIT ERROR HANDLING: Do not swallow errors silently or return vague null states. Fail fast and provide descriptive, human-readable error messages to make troubleshooting easy.
    7. ISOLATE SIDE EFFECTS: Keep pure business logic (calculations, transformations) strictly separated from side effects (API calls, DB writes, DOM manipulation). This ensures the code is easily extensible and testable.
    8. INTENT-REVEALING BUT CONCISE NAMING: Use descriptive names that explain the "what", but avoid excessively long names (e.g., use 'fetchUser' instead of 'fetchUserRecordFromDatabaseForProfile'). Only use comments to explain the "why" behind complex business rules.
    9. SANE STATE MANAGEMENT: Avoid brittle state passed through deep property drilling. Keep state isolated but easily accessible to the boundaries that need it.
    10. EXPLICIT DATA CONTRACTS: Define clear shapes for your data using types, interfaces, or detailed docstrings. A human reader should never have to guess what properties exist on an object passed between functions.

    RULES FOR RESPONSE FORMATTING:
    1. NEVER output an entire file unless explicitly asked to do so.
    2. When suggesting changes, ONLY output the specific blocks or lines that need modification.
    3. Clearly state which file you are modifying and provide a few lines of surrounding context.
    4. Think step-by-step: Briefly explain your architectural reasoning BEFORE writing code.
  </system_instructions>

  <directory_structure>
EOF

# 1. Print Directory Index
printf "%s\n" "${FILES[@]}" | sort | awk -F'/' '{
  path=""
  for(i=1; i<=NF; i++) {
    path = path ? path"/"$i :$i
    if (!seen[path]) {
      seen[path]=1
      indent=""
      for(j=1; j<i; j++) indent = indent"  "
      if (i == NF) {
        print indent "- " $i
      } else {
        print indent "- " $i "/"
      }
    }
  }
}' >>"$TEMP_FILE"

cat <<'EOF' >>"$TEMP_FILE"
  </directory_structure>

  <files>
EOF

# 2. Print File Contents inside CDATA blocks
count=0

for file_path in "${FILES[@]}"; do
  ((count++))
  display_path=${file_path#./}

  echo -ne "\r⏳ Processing ($count/$FILE_COUNT):$display_path\033[K" >&2

  echo "    <file path=\"$display_path\">" >>"$TEMP_FILE"
  echo "      <![CDATA[" >>"$TEMP_FILE"

  # Inject raw file contents AND safely escape ']]>' to prevent XML breakage
  sed 's/]]>/]]]]><![CDATA[>/g' "$file_path" >>"$TEMP_FILE"

  echo "" >>"$TEMP_FILE"
  echo "      ]]>" >>"$TEMP_FILE"
  echo "    </file>" >>"$TEMP_FILE"
done

echo -e "\n" >&2

cat <<'EOF' >>"$TEMP_FILE"
  </files>
</repository_context>
EOF

# --- Automated Secret Scanning on Temp File ---
echo "🔍 Scanning consolidated file for secrets..."
if command -v trufflehog &>/dev/null; then
  if trufflehog filesystem "$TEMP_FILE" --fail; then
    echo "✅ Clean: No secrets detected."
  else
    echo "🚨 FATAL: TruffleHog found potential secrets!"
    echo "   The output file has NOT been saved to protect your credentials."
    echo "   Scrub the secrets from your source files and re-run this script."
    rm "$TEMP_FILE"
    exit 1
  fi
else
  echo "⚠️  WARNING: TruffleHog binary not found in PATH. Skipping automated secret scan."
fi

# --- Finalize and Move File ---
mkdir -p "$(dirname "$OUTPUT_FILE")" || {
  echo "❌ FATAL: Could not create directory for $OUTPUT_FILE"
  rm "$TEMP_FILE"
  exit 1
}

mv "$TEMP_FILE" "$OUTPUT_FILE"

# --- Size Calculation & Warnings ---
FILE_SIZE_BYTES=$(wc -c <"$OUTPUT_FILE" | tr -d ' ')
FILE_SIZE_HUMAN=$(du -h "$OUTPUT_FILE" | cut -f1)
ESTIMATED_TOKENS=$((FILE_SIZE_BYTES / 4))

echo "✅ Process complete. Results saved to: $OUTPUT_FILE ($FILE_SIZE_HUMAN)"

if [ "$FILE_SIZE_BYTES" -gt "$SIZE_WARNING_THRESHOLD" ]; then
  echo "⚠️  WARNING: The generated file is quite large ($FILE_SIZE_HUMAN)."
  echo "    This is roughly ~$ESTIMATED_TOKENS tokens. Ensure your LLM has an adequate context window!"
fi
