#!/bin/bash
# Used to consolidate a codebase into an LLM-optimized single XML file.

# ==========================================
# 1. Configuration & Defaults
# ==========================================
OUTPUT_FILE="files-consolidated.xml"
TARGET_DIRS=()
SIZE_WARNING_THRESHOLD=500000 # ~125k-150k LLM tokens
MAX_SINGLE_FILE_SIZE=256000   # 250KB limit per file

EXCLUDE_DIRS=("node_modules" "dist" "build" "public" "vendor" "bin" "__pycache__" "venv" ".venv" ".next" "out" ".git" ".idea" ".vscode" ".terraform" ".local")

EXCLUDE_FILES=(
  "go.sum" "package-lock.json" "yarn.lock" "pnpm-lock.yaml" "poetry.lock"
  "*.tfstate" "*.tfstate.backup" "*.min.js" "*.min.css" "*.map" ".DS_Store"
  ".terraform.lock.hcl" ".terraform.lock.hcl*"
  "*.pem" "*.key" "*.crt" "*.cer" "*.p12" "*.pfx" "id_rsa*" ".env*" "secrets.*"
  "*.sqlite" "*.sqlite3" "*.db" "*.log"
)

# Global State
DISCOVERED_FILES=()

# ==========================================
# 2. Utilities & Error Handling
# ==========================================
log_info() { echo -e "📝 $1"; }
log_warn() { echo -e "⚠️  $1" >&2; }
log_error() { echo -e "🚨 $1" >&2; }
log_success() { echo -e "✅ $1"; }
die() {
  log_error "$1"
  exit 1
}

# ==========================================
# 3. Core Logic & Validation
# ==========================================
is_valid_target_file() {
  local file_path="$1"

  # 1. Size Check
  local actual_size
  actual_size=$(wc -c <"$file_path" 2>/dev/null)
  if [ "$actual_size" -gt "$MAX_SINGLE_FILE_SIZE" ]; then
    log_warn "Skipping massive file: $file_path ($actual_size bytes)"
    return 1
  fi

  # 2. Prevent Recursive Inclusion
  if head -n 1 "$file_path" 2>/dev/null | grep -q "<!-- @GENERATED_CONSOLIDATED_PAYLOAD -->"; then
    return 1
  fi

  # 3. Binary Check
  if file -b --mime-encoding "$file_path" | grep -q "binary"; then
    return 1
  fi

  return 0
}

is_explicitly_excluded() {
  local file_path="$1"

  # Directory check
  for ex_dir in "${EXCLUDE_DIRS[@]}"; do
    if [[ "/$file_path/" == *"/$ex_dir/"* ]]; then return 0; fi
  done

  # File check
  local basename_file
  basename_file=$(basename "$file_path")
  for ex_file in "${EXCLUDE_FILES[@]}"; do
    case "$basename_file" in
    $ex_file) return 0 ;;
    esac
  done

  return 1 # Not excluded
}

# ==========================================
# 4. File Discovery
# ==========================================
discover_via_git() {
  log_info "🐙 Git repository detected. Using git to resolve files..."

  while IFS= read -r -d '' file_path; do
    [ -f "$file_path" ] || continue
    is_explicitly_excluded "$file_path" && continue
    is_valid_target_file "$file_path" || continue

    DISCOVERED_FILES+=("$file_path")
  done < <(git ls-files -z --cached --others --exclude-standard -- "${TARGET_DIRS[@]}" 2>/dev/null)
}

discover_via_find() {
  log_info "📁 No Git repository detected. Falling back to standard find..."

  # Build Prune Logic to prevent find from crawling massive excluded folders
  local prune_args=()
  for dir in "${EXCLUDE_DIRS[@]}"; do
    prune_args+=("-type" "d" "-name" "$dir" "-prune" "-o")
  done
  for file in "${EXCLUDE_FILES[@]}"; do
    prune_args+=("-name" "$file" "-prune" "-o")
  done

  while IFS= read -r -d '' file_path; do
    is_valid_target_file "$file_path" || continue
    DISCOVERED_FILES+=("$file_path")
  done < <(find "${TARGET_DIRS[@]}" "${prune_args[@]}" -type f -print0 2>/dev/null)
}

# ==========================================
# 5. XML Generation
# ==========================================
generate_system_instructions() {
  cat <<'EOF'
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
    7. ISOLATE SIDE EFFECTS: Keep pure business logic strictly separated from side effects (API calls, DB writes, DOM manipulation).
    8. INTENT-REVEALING BUT CONCISE NAMING: Use descriptive names that explain the "what", but avoid excessively long names. Only use comments to explain the "why".
    9. SANE STATE MANAGEMENT: Avoid brittle state passed through deep property drilling. Keep state isolated but easily accessible.
    10. EXPLICIT DATA CONTRACTS: Define clear shapes for your data using types, interfaces, or detailed docstrings.
    11. ENDURING COMMENTS ONLY: Never write conversational comments, changelog-style comments (e.g., `// FIX: updated per request`), or meta-comments about the prompt. Comments must only explain the enduring 'why' of the code's permanent business logic.

    RULES FOR RESPONSE FORMATTING:
    1. NEVER output an entire file unless explicitly asked to do so.
    2. When suggesting changes, ONLY output the specific blocks or lines that need modification.
    3. Clearly state which file you are modifying and provide a few lines of surrounding context.
    4. Think step-by-step: Briefly explain your architectural reasoning BEFORE writing code.
  </system_instructions>

  <directory_structure>
EOF
}

generate_directory_tree() {
  printf "%s\n" "${DISCOVERED_FILES[@]}" | sort | awk -F'/' '{
    path=""
    for(i=1; i<=NF; i++) {
      path = path ? path"/"$i :$i
      if (!seen[path]) {
        seen[path]=1
        indent=""
        for(j=1; j<i; j++) indent = indent"  "
        if (i == NF) print indent "- " $i
        else print indent "- " $i "/"
      }
    }
  }'
}

generate_file_contents() {
  local count=0
  local total=${#DISCOVERED_FILES[@]}

  for file_path in "${DISCOVERED_FILES[@]}"; do
    ((count++))
    local display_path=${file_path#./}

    echo -ne "\r⏳ Processing ($count/$total):$display_path\033[K" >&2

    echo "    <file path=\"$display_path\">"
    echo "      <![CDATA["
    sed 's/]]>/]]]]><![CDATA[>/g' "$file_path"
    echo -e "\n      ]]>\n    </file>"
  done
  echo -e "\n" >&2
}

# ==========================================
# 6. Security Scanning
# ==========================================
run_security_scan() {
  local target_file="$1"
  log_info "🔍 Scanning consolidated file for secrets..."

  if command -v trufflehog &>/dev/null; then
    if trufflehog filesystem "$target_file" --fail; then
      log_success "Clean: No secrets detected."
    else
      log_error "FATAL: TruffleHog found potential secrets!"
      echo "Scrub the secrets from your source files and re-run this script."
      rm "$target_file"
      exit 1
    fi
  else
    log_warn "TruffleHog binary not found in PATH. Skipping automated secret scan."
  fi
}

# ==========================================
# 7. Main Orchestration
# ==========================================
main() {
  # Parse Arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
    --output | -o)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -*) die "Unknown parameter passed: $1" ;;
    *)
      TARGET_DIRS+=("$1")
      shift
      ;;
    esac
  done

  # Setup defaults
  EXCLUDE_FILES+=("$(basename "$OUTPUT_FILE")")
  if [ ${#TARGET_DIRS[@]} -eq 0 ]; then TARGET_DIRS=("."); fi

  log_info "Output intended for: $OUTPUT_FILE"

  # Discover Files
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    discover_via_git
  else
    discover_via_find
  fi

  local file_count=${#DISCOVERED_FILES[@]}
  if [ "$file_count" -eq 0 ]; then
    log_warn "No text files found matching the criteria."
    exit 0
  fi

  log_info "📦 Compiling $file_count text file(s) into LLM context format..."

  # Generate Output
  local temp_file
  temp_file=$(mktemp)

  {
    generate_system_instructions
    generate_directory_tree
    echo -e "  </directory_structure>\n\n  <files>"
    generate_file_contents
    echo -e "  </files>\n</repository_context>"
  } >"$temp_file"

  run_security_scan "$temp_file"

  # Finalize
  mkdir -p "$(dirname "$OUTPUT_FILE")" || die "Could not create directory for $OUTPUT_FILE"
  mv "$temp_file" "$OUTPUT_FILE"

  local file_size_bytes
  file_size_bytes=$(wc -c <"$OUTPUT_FILE" | tr -d ' ')
  local file_size_human
  file_size_human=$(du -h "$OUTPUT_FILE" | cut -f1)

  log_success "Process complete. Results saved to: $OUTPUT_FILE ($file_size_human)"

  if [ "$file_size_bytes" -gt "$SIZE_WARNING_THRESHOLD" ]; then
    log_warn "The generated file is quite large ($file_size_human)."
    echo "    Ensure your LLM has an adequate context window!"
  fi
}

main "$@"
