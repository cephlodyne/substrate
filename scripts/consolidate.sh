#!/bin/bash
# Consolidates a codebase into LLM-optimized, auto-chunked XML files.

set -uo pipefail

# ==========================================
# 1. Configuration & Defaults
# ==========================================
OUTPUT_FILE="files-consolidated.xml"
TARGET_DIRS=()
SIZE_WARNING_THRESHOLD=500000 # ~125k-150k LLM tokens
MAX_SINGLE_FILE_SIZE=256000   # 250KB limit per individual source file
MAX_CHUNK_SIZE=130000         # 130KB per XML output chunk (safely under 140k-char upload limits)

EXCLUDE_DIRS=(
  "node_modules" "dist" "build" "public" "vendor" "bin"
  "__pycache__" "venv" ".venv" ".next" "out"
  ".git" ".idea" ".vscode" ".terraform" ".local"
)

EXCLUDE_FILES=(
  "go.sum" "package-lock.json" "yarn.lock" "pnpm-lock.yaml" "poetry.lock"
  "*.tfstate" "*.tfstate.*" "*.min.js" "*.min.css" "*.map" ".DS_Store"
  ".terraform.lock.hcl" ".terraform.lock.hcl*"
  "*.pem" "*.key" "*.crt" "*.cer" "*.p12" "*.pfx" "id_rsa*" ".env*" "secrets.*"
  "*.sqlite" "*.sqlite3" "*.db" "*.log"
  "combined_config.auto.tfvars.json" "*.tfvars.json"
  "files-consolidated*.xml" "files-consolidated*.txt" "combined_terraform_files.txt"
)

# Global State
DISCOVERED_FILES=()
TEMP_BODY_CHUNKS=()
CHUNK_MANIFEST=()

# ==========================================
# 2. Utilities & Cleanup Trap
# ==========================================
log_info() { echo -e "📝 $1"; }
log_warn() { echo -e "⚠️  $1" >&2; }
log_error() { echo -e "🚨 $1" >&2; }
log_success() { echo -e "✅ $1"; }
die() {
  log_error "$1"
  exit 1
}

cleanup() {
  if [ "${#TEMP_BODY_CHUNKS[@]}" -gt 0 ]; then
    for tmp in "${TEMP_BODY_CHUNKS[@]}"; do
      [ -f "$tmp" ] && rm -f "$tmp"
    done
  fi
}
trap cleanup EXIT INT TERM

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TARGET_DIRS...]

Options:
  -o, --output FILE       Output filename (default: $OUTPUT_FILE)
  -c, --chunk-size BYTES  Max bytes per XML chunk; 0 disables chunking (default: $MAX_CHUNK_SIZE)
  -m, --max-file BYTES    Skip individual files larger than BYTES (default: $MAX_SINGLE_FILE_SIZE)
  -x, --exclude PATTERN   Additional file/dir glob pattern to exclude (can be used multiple times)
  -h, --help              Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") -x editor.html
  $(basename "$0") 10-bootstrap 60-env-platform modules
EOF
  exit 0
}

escape_xml_attr() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//\"/&quot;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

# ==========================================
# 3. Core Logic & Validation
# ==========================================
is_valid_target_file() {
  local file_path="$1"

  # 1. Size Check
  local actual_size
  actual_size=$(wc -c <"$file_path" 2>/dev/null | tr -d ' ') || return 1
  if [ "$actual_size" -eq 0 ]; then
    return 1
  fi
  if [ "$actual_size" -gt "$MAX_SINGLE_FILE_SIZE" ]; then
    log_warn "Skipping large file: $file_path ($actual_size bytes > $MAX_SINGLE_FILE_SIZE limit)"
    return 1
  fi

  # 2. Prevent Recursive Inclusion
  if head -n 1 "$file_path" 2>/dev/null | grep -q "<!-- @GENERATED_CONSOLIDATED_PAYLOAD"; then
    return 1
  fi

  # 3. Fast Binary Check (grep -I treats binary files as non-matching)
  if ! grep -Iq . "$file_path" 2>/dev/null; then
    return 1
  fi

  return 0
}

is_explicitly_excluded() {
  local file_path="$1"
  local normalized_path="/${file_path#./}/"

  # Directory check
  for ex_dir in "${EXCLUDE_DIRS[@]}"; do
    if [[ "$normalized_path" == *"/$ex_dir/"* ]]; then
      return 0
    fi
  done

  # File check
  local basename_file
  basename_file=$(basename "$file_path")
  for ex_file in "${EXCLUDE_FILES[@]}"; do
    # shellcheck disable=SC2254
    case "$basename_file" in
    $ex_file) return 0 ;;
    esac
  done

  return 1
}

# ==========================================
# 4. File Discovery
# ==========================================
discover_via_git() {
  log_info "🐙 Git repository detected. Using git to resolve files..."

  while IFS= read -r -d '' file_path; do
    file_path="${file_path#./}"
    [ -f "$file_path" ] || continue
    is_explicitly_excluded "$file_path" && continue
    is_valid_target_file "$file_path" || continue

    DISCOVERED_FILES+=("$file_path")
  done < <(git ls-files -z --cached --others --exclude-standard -- "${TARGET_DIRS[@]}" 2>/dev/null)
}

discover_via_find() {
  log_info "📁 No Git repository detected. Falling back to standard find..."

  local prune_args=()
  for dir in "${EXCLUDE_DIRS[@]}"; do
    prune_args+=("-type" "d" "-name" "$dir" "-prune" "-o")
  done
  for file in "${EXCLUDE_FILES[@]}"; do
    prune_args+=("-name" "$file" "-prune" "-o")
  done

  while IFS= read -r -d '' file_path; do
    file_path="${file_path#./}"
    [ -f "$file_path" ] || continue
    is_explicitly_excluded "$file_path" && continue
    is_valid_target_file "$file_path" || continue

    DISCOVERED_FILES+=("$file_path")
  done < <(find "${TARGET_DIRS[@]}" "${prune_args[@]}" -type f -print0 2>/dev/null)
}

sort_discovered_files() {
  local sorted=()
  while IFS= read -r line; do
    [ -n "$line" ] && sorted+=("$line")
  done < <(printf "%s\n" "${DISCOVERED_FILES[@]}" | LC_ALL=C sort -u)
  DISCOVERED_FILES=("${sorted[@]}")
}

# ==========================================
# 5. XML Metadata & Context Generators
# ==========================================
generate_system_instructions() {
  cat <<'EOF'
  <system_instructions>
    You are an expert software architect. Review the 'directory_structure', 'architecture_graph', and 'chunk_routing_map' to understand the project topology, then review the code in the 'files' section.
    
    MULTI-PART CONTEXT AWARENESS:
    Check the 'part' and 'total_parts' attributes on the root <repository_context> tag. If total_parts > 1, the codebase is split across multiple XML files. Use <chunk_routing_map> in Part 1 to locate which part contains any file you need to inspect.

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
EOF
}

generate_directory_tree() {
  echo "  <directory_structure>"
  printf "%s\n" "${DISCOVERED_FILES[@]}" | awk -F'/' '{
    path=""
    for(i=1; i<=NF; i++) {
      path = path ? path"/"$i : $i
      if (!seen[path]) {
        seen[path]=1
        indent=""
        for(j=1; j<i; j++) indent = indent"  "
        if (i == NF) print indent "- " $i
        else print indent "- " $i "/"
      }
    }
  }'
  echo "  </directory_structure>"
}

# Automatically extracts Terraform module calls & contract references for LLM navigation
generate_architecture_graph() {
  echo "  <architecture_graph>"
  for file_path in "${DISCOVERED_FILES[@]}"; do
    [[ "$file_path" == *.tf ]] || continue

    local mod_sources
    mod_sources=$(awk -F'"' '/^[[:space:]]*source[[:space:]]*=[[:space:]]*"\.\./ {print $2}' "$file_path" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

    local contracts
    contracts=$(awk -F'"' '/^[[:space:]]*(contract_scope|secret)[[:space:]]*=[[:space:]]*"/ {print $2}' "$file_path" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

    if [ -n "$mod_sources" ] || [ -n "$contracts" ]; then
      local safe_path
      safe_path=$(escape_xml_attr "$file_path")
      printf '    <relation file="%s"' "$safe_path"
      [ -n "$mod_sources" ] && printf ' modules="%s"' "$(escape_xml_attr "$mod_sources")"
      [ -n "$contracts" ] && printf ' contracts="%s"' "$(escape_xml_attr "$contracts")"
      printf ' />\n'
    fi
  done
  echo "  </architecture_graph>"
}

# ==========================================
# 6. Chunk Assembly
# ==========================================
build_file_body_chunks() {
  local count=0
  local total=${#DISCOVERED_FILES[@]}
  local part=1
  local current_body
  current_body=$(mktemp) || die "Failed to create temporary file"
  TEMP_BODY_CHUNKS+=("$current_body")

  # Reserve ~18KB in Part 1 for <system_instructions>, <directory_structure>,
  # <architecture_graph>, and <chunk_routing_map>.
  local part1_header_overhead=18000

  for file_path in "${DISCOVERED_FILES[@]}"; do
    count=$((count + 1))
    local display_path="${file_path#./}"

    echo -ne "\r⏳ Processing ($count/$total): $display_path\033[K" >&2

    local file_bytes
    file_bytes=$(wc -c <"$file_path" 2>/dev/null | tr -d ' ')
    local file_lines
    file_lines=$(wc -l <"$file_path" 2>/dev/null | tr -d ' ')
    local current_chunk_bytes
    current_chunk_bytes=$(wc -c <"$current_body" 2>/dev/null | tr -d ' ')

    local overhead=500
    if [ "$part" -eq 1 ]; then
      overhead=$part1_header_overhead
    fi

    # Roll over to a new chunk if adding this file exceeds MAX_CHUNK_SIZE
    if [ "$MAX_CHUNK_SIZE" -gt 0 ] && [ "$current_chunk_bytes" -gt 0 ] && [ $((current_chunk_bytes + file_bytes + overhead + 200)) -gt "$MAX_CHUNK_SIZE" ]; then
      part=$((part + 1))
      current_body=$(mktemp) || die "Failed to create temporary file"
      TEMP_BODY_CHUNKS+=("$current_body")
    fi

    local escaped_path
    escaped_path=$(escape_xml_attr "$display_path")

    # Record file routing for Part 1's <chunk_routing_map>
    CHUNK_MANIFEST+=("    <entry part=\"$part\" lines=\"$file_lines\" bytes=\"$file_bytes\" path=\"$escaped_path\" />")

    {
      echo "    <file path=\"$escaped_path\" lines=\"$file_lines\" bytes=\"$file_bytes\">"
      echo "      <![CDATA["
      sed 's/]]>/]]]]><![CDATA[>/g' "$file_path"
      echo -e "\n      ]]>\n    </file>"
    } >>"$current_body"
  done

  echo -e "\n" >&2
}

# ==========================================
# 7. Security Scanning
# ==========================================
run_security_scan() {
  local target_file="$1"

  if command -v trufflehog &>/dev/null; then
    if ! trufflehog filesystem "$target_file" --fail >/dev/null 2>&1; then
      log_error "FATAL: TruffleHog detected potential secrets in $target_file!"
      echo "Scrub the secrets from your source files and re-run this script." >&2
      rm -f "$target_file"
      exit 1
    fi
  fi
}

# ==========================================
# 8. Main Orchestration
# ==========================================
main() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
    --output | -o)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --chunk-size | -c)
      MAX_CHUNK_SIZE="$2"
      shift 2
      ;;
    --max-file | -m)
      MAX_SINGLE_FILE_SIZE="$2"
      shift 2
      ;;
    --exclude | -x)
      EXCLUDE_FILES+=("$2")
      EXCLUDE_DIRS+=("$2")
      shift 2
      ;;
    --help | -h)
      usage
      ;;
    -*)
      die "Unknown parameter passed: $1 (use --help for usage)"
      ;;
    *)
      TARGET_DIRS+=("$1")
      shift
      ;;
    esac
  done

  local base_name="${OUTPUT_FILE%.*}"
  local ext="${OUTPUT_FILE##*.}"
  if [ "$base_name" = "$OUTPUT_FILE" ]; then
    ext="xml"
  fi

  EXCLUDE_FILES+=("$(basename "$OUTPUT_FILE")" "$(basename "$base_name")-part*.$ext")
  if [ "${#TARGET_DIRS[@]}" -eq 0 ]; then
    TARGET_DIRS=(".")
  fi

  log_info "Target output: $OUTPUT_FILE (Max chunk size: ${MAX_CHUNK_SIZE} bytes)"

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

  sort_discovered_files
  log_info "📦 Compiling $file_count text file(s) into LLM context format..."

  build_file_body_chunks

  local total_parts=${#TEMP_BODY_CHUNKS[@]}
  mkdir -p "$(dirname "$OUTPUT_FILE")" || die "Could not create directory for $OUTPUT_FILE"

  # Remove stale outputs from previous runs
  rm -f "$OUTPUT_FILE" "${base_name}-part"*."${ext}"

  if command -v trufflehog &>/dev/null; then
    log_info "🔍 Scanning generated chunks with TruffleHog..."
  else
    log_warn "TruffleHog binary not found in PATH. Skipping automated secret scan."
  fi

  local total_bytes=0

  for i in "${!TEMP_BODY_CHUNKS[@]}"; do
    local body_file="${TEMP_BODY_CHUNKS[$i]}"
    local part_num=$((i + 1))
    local final_path="$OUTPUT_FILE"

    if [ "$total_parts" -gt 1 ]; then
      final_path="${base_name}-part${part_num}.${ext}"
    fi

    {
      echo "<!-- @GENERATED_CONSOLIDATED_PAYLOAD -->"
      echo "<repository_context part=\"$part_num\" total_parts=\"$total_parts\" total_files=\"$file_count\">"

      if [ "$part_num" -eq 1 ]; then
        generate_system_instructions
        echo ""
        generate_directory_tree
        echo ""
        generate_architecture_graph
        echo ""
        echo "  <chunk_routing_map>"
        printf "%s\n" "${CHUNK_MANIFEST[@]}"
        echo "  </chunk_routing_map>"
      else
        echo "  <!-- Continuation chunk ($part_num of $total_parts). Refer to Part 1 for system_instructions, directory_structure, and chunk_routing_map. -->"
      fi

      echo ""
      echo "  <files>"
      cat "$body_file"
      echo "  </files>"
      echo "</repository_context>"
    } >"$final_path"

    run_security_scan "$final_path"

    local chunk_bytes
    chunk_bytes=$(wc -c <"$final_path" | tr -d ' ')
    total_bytes=$((total_bytes + chunk_bytes))

    local chunk_human
    chunk_human=$(du -h "$final_path" | cut -f1)
    log_success "Saved ($part_num/$total_parts): $final_path ($chunk_human, ${chunk_bytes} bytes)"
  done

  if [ "$total_bytes" -gt "$SIZE_WARNING_THRESHOLD" ]; then
    log_warn "Total payload across $total_parts file(s) is $((total_bytes / 1024)) KB."
    echo "    Ensure your LLM has an adequate context window!"
  fi
}

main "$@"
