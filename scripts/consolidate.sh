#!/bin/bash
# Used to consolidate a codebase into an LLM-optimized single XML file.
# Automatically filters out binary files, previous runs, and common massive directories.

# --- Configuration & Defaults ---
OUTPUT_FILE="files-consolidated.xml"
TARGET_DIRS=()
SIZE_WARNING_THRESHOLD=500000 # ~125k-150k LLM tokens

# Standard directories to always ignore (Used primarily for the 'find' fallback and now enforced in git loop)
EXCLUDE_DIRS=("node_modules" "dist" "build" "public" "vendor" "bin" "__pycache__" "venv" ".venv" ".next" "out" ".git" ".idea" ".vscode" ".terraform" ".local")

# Specific token-heavy, generated, OR SENSITIVE files
EXCLUDE_FILES=(
  # Dependencies & Generated
  "go.sum" "package-lock.json" "yarn.lock" "pnpm-lock.yaml" "poetry.lock"
  "*.tfstate" "*.tfstate.backup" "*.min.js" "*.min.css" "*.map" ".DS_Store"
  ".terraform.lock.hcl" ".terraform.lock.hcl*"
  # Secrets, Keys, and Environments
  "*.pem" "*.key" "*.crt" "*.cer" "*.p12" "*.pfx" "id_rsa*" ".env*" "secrets.*"
  # Local Databases & Logs
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
  echo "🐙 Git repository detected. Using git to resolve files (and enforcing manual exclusions)..."

  while IFS= read -r -d '' file_path; do
    [ -f "$file_path" ] || continue # Ensure it's a file

    skip=false

    # 1. Check against excluded directories
    # By wrapping both sides in slashes, we ensure we match whole directory names
    # e.g., "src/node_modules/pkg" becomes "/src/node_modules/pkg/" and matches "/node_modules/"
    for ex_dir in "${EXCLUDE_DIRS[@]}"; do
      if [[ "/$file_path/" == *"/$ex_dir/"* ]]; then
        skip=true
        break
      fi
    done

    # 2. Check against our manual exclusion list for files (Globs supported)
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

    # Skip previously generated LLM context files
    if head -n 1 "$file_path" 2>/dev/null | grep -q "<!-- @GENERATED_LLM_CONTEXT: IGNORE_THIS_FILE -->"; then
      continue
    fi

    if ! file -b --mime-encoding "$file_path" | grep -q "binary"; then
      FILES+=("$file_path")
    fi
    # git ls-files: -z (null terminated), --cached (tracked), --others (untracked), --exclude-standard (respect .gitignore)
  done < <(git ls-files -z --cached --others --exclude-standard -- "${SEARCH_BASE[@]}" 2>/dev/null)

else
  echo "📁 No Git repository detected. Falling back to standard find..."

  # Build Prune Logic for find
  PRUNE_LOGIC=()
  for dir in "${EXCLUDE_DIRS[@]}"; do
    PRUNE_LOGIC+=("-type" "d" "-name" "$dir" "-prune" "-o")
  done
  for file in "${EXCLUDE_FILES[@]}"; do
    PRUNE_LOGIC+=("-name" "$file" "-prune" "-o")
  done

  while IFS= read -r -d '' file_path; do
    if head -n 1 "$file_path" 2>/dev/null | grep -q "<!-- @GENERATED_LLM_CONTEXT: IGNORE_THIS_FILE -->"; then
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
<!-- @GENERATED_LLM_CONTEXT: IGNORE_THIS_FILE -->
<repository_context>
  <system_instructions>
    You are an expert software engineer and architect. Review the 'directory_structure' to understand the project architecture, then review the code in the 'files' section. 
    
    CRITICAL RULES:
    1. NEVER output an entire file unless explicitly asked to do so.
    2. When suggesting changes, ONLY output the specific blocks or lines that need modification.
    3. Clearly state which file you are modifying and provide surrounding context (a few lines above and below).
    4. Think step-by-step: Briefly explain your reasoning BEFORE writing code.
    5. Be direct, concise, and professional.
  </system_instructions>

  <directory_structure>
EOF

# 1. Print Directory Index
printf "%s\n" "${FILES[@]}" | sort | awk -F'/' '{
  path=""
  for(i=1; i<=NF; i++) {
    path = path ? path"/"$i : $i
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

echo "  </directory_structure>" >>"$TEMP_FILE"
echo "" >>"$TEMP_FILE"
echo "  <files>" >>"$TEMP_FILE"

# 2. Print File Contents inside CDATA blocks
count=0

for file_path in "${FILES[@]}"; do
  ((count++))
  display_path=${file_path#./}

  echo -ne "\r⏳ Processing ($count/$FILE_COUNT): $display_path\033[K" >&2

  echo "    <file path=\"$display_path\">" >>"$TEMP_FILE"
  echo "      <![CDATA[" >>"$TEMP_FILE"

  # Inject raw file contents AND safely escape ']]>' to prevent XML breakage
  sed 's/]]>/]]]]><![CDATA[>/g' "$file_path" >>"$TEMP_FILE"

  echo "" >>"$TEMP_FILE"
  echo "      ]]>" >>"$TEMP_FILE"
  echo "    </file>" >>"$TEMP_FILE"
done

echo -e "\n" >&2

echo "  </files>" >>"$TEMP_FILE"
echo "</repository_context>" >>"$TEMP_FILE"

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
  echo "   Please manually verify the output for API keys and credentials before sharing."
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
