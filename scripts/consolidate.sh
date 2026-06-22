#!/bin/bash
# Used to consolidate multiple files into an LLM-optimized single file.

# --- Configuration & Defaults ---
AUTO_DETECT=1
GO_MODE=0
WEB_MODE=0
TF_MODE=0
PY_MODE=0
TARGET_DIRS=()
OUTPUT_FILE="files-consolidated.xml"
SIZE_WARNING_THRESHOLD=500000 # 500KB (Roughly ~125k-150k LLM tokens)

# Base exclusions (always ignored to save LLM tokens)
# Note: Hidden directories (.*) are now automatically ignored dynamically.
EXCLUDE_DIRS=("node_modules" "dist" "build" "public" "vendor" "bin" "__pycache__")

# Specific token-heavy files that offer no logic value to LLMs
EXCLUDE_FILES=("go.sum" "package-lock.json" "yarn.lock" "pnpm-lock.yaml" "poetry.lock" "*.tfstate" "*.tfstate.backup")

# --- Parse Arguments ---
while [[ "$#" -gt 0 ]]; do
  case $1 in
  --go | -g)
    GO_MODE=1
    AUTO_DETECT=0
    shift
    ;;
  --web | --svelte | -w | -s)
    WEB_MODE=1
    AUTO_DETECT=0
    shift
    ;;
  --tofu | --terraform | -t)
    TF_MODE=1
    AUTO_DETECT=0
    shift
    ;;
  --python | -p)
    PY_MODE=1
    AUTO_DETECT=0
    shift
    ;;
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

# --- Determine Search Base ---
if [ ${#TARGET_DIRS[@]} -gt 0 ]; then
  SEARCH_BASE=("${TARGET_DIRS[@]}")
else
  SEARCH_BASE=(".")
fi

# --- Auto-Detect Project Types ---
if [ "$AUTO_DETECT" -eq 1 ]; then
  echo "🤖 Auto-detecting project types in ${SEARCH_BASE[*]}..."

  # Scan up to 3 levels deep for defining files OR standard extensions
  if [ -n "$(find "${SEARCH_BASE[@]}" -maxdepth 3 \( -name 'go.mod' -o -name '*.go' \) -print -quit 2>/dev/null)" ]; then GO_MODE=1; fi
  if [ -n "$(find "${SEARCH_BASE[@]}" -maxdepth 3 \( -name 'package.json' -o -name '*.ts' -o -name '*.js' -o -name '*.svelte' \) -print -quit 2>/dev/null)" ]; then WEB_MODE=1; fi
  if [ -n "$(find "${SEARCH_BASE[@]}" -maxdepth 3 \( -name '*.tf' -o -name '*.tofu' \) -print -quit 2>/dev/null)" ]; then TF_MODE=1; fi
  if [ -n "$(find "${SEARCH_BASE[@]}" -maxdepth 3 \( -name 'requirements.txt' -o -name 'pyproject.toml' -o -name '*.py' \) -print -quit 2>/dev/null)" ]; then PY_MODE=1; fi
fi

# --- Build Extension Lists ---
EXTENSIONS=()
add_extension() {
  if [ ${#EXTENSIONS[@]} -gt 0 ]; then EXTENSIONS+=("-o"); fi
  EXTENSIONS+=("-name" "$1")
}

# 1. Base/Default Files
add_extension "*.md"
add_extension "*.sh"
add_extension "*.yaml"
add_extension "*.yml"
add_extension "Dockerfile"
add_extension "Makefile"

# 2. Golang Files
if [ "$GO_MODE" -eq 1 ]; then
  echo "✅ Go mode enabled: Including .go, go.mod"
  add_extension "*.go"
  add_extension "go.mod"
fi

# 3. Web / Svelte / JS Files
if [ "$WEB_MODE" -eq 1 ]; then
  echo "✅ Web mode enabled: Including .ts, .js, .svelte, .css, .html, .json"
  add_extension "*.svelte"
  add_extension "*.ts"
  add_extension "*.tsx"
  add_extension "*.js"
  add_extension "*.jsx"
  add_extension "*.css"
  add_extension "*.html"
  add_extension "*.json"
fi

# 4. Terraform / OpenTofu Files
if [ "$TF_MODE" -eq 1 ]; then
  echo "✅ Infra mode enabled: Including .tf, .tofu, .tfvars, .hcl"
  add_extension "*.tf"
  add_extension "*.tofu"
  add_extension "*.tfvars"
  add_extension "*.hcl"
fi

# 5. Python Files
if [ "$PY_MODE" -eq 1 ]; then
  echo "✅ Python mode enabled: Including .py, requirements.txt, pyproject.toml"
  add_extension "*.py"
  add_extension "requirements.txt"
  add_extension "pyproject.toml"
fi

# --- Build Prune & Exclude Logic ---
PRUNE_LOGIC=()

# IMPROVEMENT: Automatically prune ALL hidden directories (e.g., .git, .venv), but don't prune '.' or '..'
PRUNE_LOGIC+=("-type" "d" "-name" ".*" "!" "-name" "." "!" "-name" ".." "-prune" "-o")

for dir in "${EXCLUDE_DIRS[@]}"; do
  PRUNE_LOGIC+=("-type" "d" "-name" "$dir" "-prune" "-o")
done

for file in "${EXCLUDE_FILES[@]}"; do
  PRUNE_LOGIC+=("-name" "$file" "-prune" "-o")
done

echo "🔍 Searching in: ${SEARCH_BASE[*]}"
echo "📝 Output will be saved to: $OUTPUT_FILE"

# --- Execute Find & Store in Array ---
FILES=()
while IFS= read -r -d '' file_path; do
  FILES+=("$file_path")
done < <(find "${SEARCH_BASE[@]}" "${PRUNE_LOGIC[@]}" -type f \( "${EXTENSIONS[@]}" \) -print0 2>/dev/null)

FILE_COUNT=${#FILES[@]}

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "⚠️ No files found matching the criteria."
  exit 0
fi

echo "📦 Compiling $FILE_COUNT file(s) into LLM context format..."

# --- Write LLM Optimized Output ---
>"$OUTPUT_FILE"

cat <<'EOF' >>"$OUTPUT_FILE"
<repository_context>
  <system_instructions>
    You are an expert software engineer and architect. The following is a consolidated view of a codebase. 
    First, review the 'directory_structure' to understand the project architecture. 
    Then, review the files contained within the 'files' section. 
    
    CRITICAL RULES FOR YOUR RESPONSES:
    1. NEVER output an entire file unless explicitly asked to do so. This wastes context window and degrades performance.
    2. When suggesting changes, ONLY output the specific functions, blocks, or lines that need modification.
    3. Clearly state which file you are modifying and provide enough surrounding context (a few lines above and below) so the user knows exactly where to paste the changes.
    4. Think step-by-step: Briefly explain your reasoning and architectural plan BEFORE writing any code.
    5. Do not apologize or use excessive conversational filler. Be direct, concise, and professional.
  </system_instructions>

  <directory_structure>
EOF

# 1. Print Directory Index (Pure Bash/Awk Tree View)
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
}' >>"$OUTPUT_FILE"

echo "  </directory_structure>" >>"$OUTPUT_FILE"
echo "" >>"$OUTPUT_FILE"
echo "  <files>" >>"$OUTPUT_FILE"

# 2. Print File Contents
count=0

for file_path in "${FILES[@]}"; do
  ((count++))
  display_path=${file_path#./}

  filename="${display_path##*/}"
  extension="${filename##*.}"
  if [[ "$filename" == "$extension" ]]; then
    extension="text"
  fi

  echo -ne "\r⏳ Processing ($count/$FILE_COUNT): $display_path\033[K" >&2

  echo "    <file path=\"$display_path\">"
  echo '```'"$extension"

  cat "$file_path"
  echo ""

  echo '```'
  echo "    </file>"
done >>"$OUTPUT_FILE"

echo -e "\n" >&2

echo "  </files>" >>"$OUTPUT_FILE"
echo "</repository_context>" >>"$OUTPUT_FILE"

# --- Size Calculation & Warnings ---
FILE_SIZE_BYTES=$(wc -c <"$OUTPUT_FILE" | tr -d ' ')
FILE_SIZE_HUMAN=$(du -h "$OUTPUT_FILE" | cut -f1)
ESTIMATED_TOKENS=$((FILE_SIZE_BYTES / 4))

echo "✅ Process complete. Results saved to: $OUTPUT_FILE ($FILE_SIZE_HUMAN)"

if [ "$FILE_SIZE_BYTES" -gt "$SIZE_WARNING_THRESHOLD" ]; then
  echo "⚠️  WARNING: The generated file is quite large ($FILE_SIZE_HUMAN)."
  echo "    This is roughly ~$ESTIMATED_TOKENS tokens. Ensure your LLM has an adequate context window!"
fi
