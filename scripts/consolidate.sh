#!/bin/bash
# Used to consolidate a codebase into an LLM-optimized single XML file.
# Automatically filters out binary files and common massive directories.

# --- Configuration & Defaults ---
OUTPUT_FILE="files-consolidated.xml"
TARGET_DIRS=()
SIZE_WARNING_THRESHOLD=500000 # ~125k-150k LLM tokens

# Standard directories to always ignore (saves traversal time and tokens)
EXCLUDE_DIRS=("node_modules" "dist" "build" "public" "vendor" "bin" "__pycache__" "venv" ".venv" ".next" "out")

# Specific token-heavy/generated files that offer no logic value to LLMs
EXCLUDE_FILES=("go.sum" "package-lock.json" "yarn.lock" "pnpm-lock.yaml" "poetry.lock" "*.tfstate" "*.tfstate.backup" "*.min.js" "*.min.css" "*.map" ".DS_Store")

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
# Dynamically ignore the output file so we don't 'cat' it into itself
EXCLUDE_FILES+=("$(basename "$OUTPUT_FILE")")

if [ ${#TARGET_DIRS[@]} -gt 0 ]; then
  SEARCH_BASE=("${TARGET_DIRS[@]}")
else
  SEARCH_BASE=(".")
fi

# --- Build Prune & Exclude Logic ---
PRUNE_LOGIC=()

# 1. Prune all hidden directories (e.g., .git, .idea, .vscode) but keep '.' and '..'
PRUNE_LOGIC+=("-type" "d" "-name" ".*" "!" "-name" "." "!" "-name" ".." "-prune" "-o")

# 2. Prune specific heavy directories
for dir in "${EXCLUDE_DIRS[@]}"; do
  PRUNE_LOGIC+=("-type" "d" "-name" "$dir" "-prune" "-o")
done

# 3. Prune specific ignored files
for file in "${EXCLUDE_FILES[@]}"; do
  PRUNE_LOGIC+=("-name" "$file" "-prune" "-o")
done

echo "🔍 Scanning: ${SEARCH_BASE[*]}"
echo "📝 Output will be saved to: $OUTPUT_FILE"

# --- Execute Find & Filter Binaries ---
FILES=()
while IFS= read -r -d '' file_path; do
  # Check if the file is binary using its mime-encoding
  # If it is NOT binary, add it to our array
  if ! file -b --mime-encoding "$file_path" | grep -q "binary"; then
    FILES+=("$file_path")
  fi
done < <(find "${SEARCH_BASE[@]}" "${PRUNE_LOGIC[@]}" -type f -print0 2>/dev/null)

FILE_COUNT=${#FILES[@]}

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "⚠️ No text files found matching the criteria."
  exit 0
fi

echo "📦 Compiling $FILE_COUNT text file(s) into LLM context format..."

# --- Write LLM Optimized Output ---
# Ensure the destination directory exists before writing
mkdir -p "$(dirname "$OUTPUT_FILE")" || {
  echo "❌ FATAL: Could not create directory for $OUTPUT_FILE"
  exit 1
}
>"$OUTPUT_FILE"

cat <<'EOF' >>"$OUTPUT_FILE"
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
}' >>"$OUTPUT_FILE"

echo "  </directory_structure>" >>"$OUTPUT_FILE"
echo "" >>"$OUTPUT_FILE"
echo "  <files>" >>"$OUTPUT_FILE"

# 2. Print File Contents inside CDATA blocks
count=0

for file_path in "${FILES[@]}"; do
  ((count++))
  display_path=${file_path#./}

  echo -ne "\r⏳ Processing ($count/$FILE_COUNT): $display_path\033[K" >&2

  # Wrap in XML and CDATA tags to prevent syntax characters from breaking the XML tree
  echo "    <file path=\"$display_path\">" >>"$OUTPUT_FILE"
  echo "      <![CDATA[" >>"$OUTPUT_FILE"

  # Inject the raw file contents
  cat "$file_path" >>"$OUTPUT_FILE"

  # Ensure there is a newline before closing CDATA in case the file doesn't end with one
  echo "" >>"$OUTPUT_FILE"
  echo "      ]]>" >>"$OUTPUT_FILE"
  echo "    </file>" >>"$OUTPUT_FILE"
done

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

# --- Automated Secret Scanning ---
echo "🔍 Scanning consolidated file for secrets..."
if command -v trufflehog &>/dev/null; then
  if trufflehog filesystem "$OUTPUT_FILE" --fail; then
    echo "✅ Clean: No secrets detected in $OUTPUT_FILE."
  else
    echo "🚨 FATAL: TruffleHog found potential secrets in $OUTPUT_FILE!"
    echo "   Do NOT share this file with an LLM until you scrub the secrets from the source files and re-run this script."
    exit 1
  fi
else
  echo "⚠️  WARNING: TruffleHog binary not found in PATH. Skipping automated secret scan."
  echo "   Please manually verify $OUTPUT_FILE for API keys and credentials before sharing."
fi
