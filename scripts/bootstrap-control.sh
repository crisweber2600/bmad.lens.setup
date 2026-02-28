#!/usr/bin/env bash
set -euo pipefail

release_url_default="https://github.com/crisweber2600/bmad.lens.release.git"
release_branch_default="release/2.0.0"
copilot_url_default="https://github.com/crisweber2600/bmad.lens.copilot.git"
copilot_branch_default="main"
governance_url_default="https://github.com/crisweber2600/bmad.lens.governance.git"
governance_branch_default="main"

control_location=""
control_dir_arg=""
control_branch=""
release_url="$release_url_default"
release_branch="$release_branch_default"
copilot_url="$copilot_url_default"
copilot_branch="$copilot_branch_default"
governance_url="$governance_url_default"
governance_branch="$governance_branch_default"
dry_run=false
assume_yes=false

usage() {
  cat <<'EOF'
Usage:
  bootstrap-control.sh --control <path-or-git-url> [options]

Options:
  --control <value>              Control repo local path or git URL.
  --control-dir <path>           Local directory to use when --control is a git URL.
  --control-branch <name>        Optional control repo branch to enforce.

  --release-url <url>            Release repo URL (default: crisweber2600/bmad.lens.release).
  --release-branch <name>        Release branch (default: release/2.0.0).
  --copilot-url <url>            Copilot repo URL (default: crisweber2600/bmad.lens.copilot).
  --copilot-branch <name>        Copilot branch (default: main).
  --governance-url <url>         Governance repo URL (default: crisweber2600/bmad.lens.governance).
  --governance-branch <name>     Governance branch (default: main).

  --yes                          Non-interactive mode (accept defaults).
  --dry-run                      Print actions without changing files.
  -h, --help                     Show this help.
EOF
}

run() {
  if $dry_run; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

is_git_url() {
  [[ "$1" =~ ^(https://|http://|ssh://|git@) ]]
}

normalize_path() {
  local p="$1"
  if [[ "$p" =~ ^[A-Za-z]:\\ ]] && command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p"
  else
    echo "$p"
  fi
}

prompt_if_empty() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="${3:-}"
  local current_value
  current_value="${!var_name:-}"
  if [[ -n "$current_value" ]]; then
    return
  fi

  if $assume_yes; then
    printf -v "$var_name" '%s' "$default_value"
    return
  fi

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt_text [$default_value]: " current_value
    current_value="${current_value:-$default_value}"
  else
    read -r -p "$prompt_text: " current_value
  fi
  printf -v "$var_name" '%s' "$current_value"
}

ensure_repo_checkout() {
  local label="$1"
  local dir="$2"
  local url="$3"
  local branch="$4"

  if [[ -e "$dir" && ! -d "$dir/.git" ]]; then
    echo "ERROR: $label path exists but is not a git repository: $dir" >&2
    exit 1
  fi

  if [[ -d "$dir/.git" ]]; then
    run git -C "$dir" remote set-url origin "$url"
    run git -C "$dir" fetch --prune origin
  else
    run mkdir -p "$(dirname "$dir")"
    run git clone "$url" "$dir"
    run git -C "$dir" fetch --prune origin
  fi

  if ! git -C "$dir" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    echo "ERROR: Branch '$branch' not found on '$url' for $label" >&2
    exit 1
  fi

  run git -C "$dir" checkout -B "$branch" "origin/$branch"
  run git -C "$dir" pull --ff-only origin "$branch"
}

ensure_control_gitignore() {
  local control_dir="$1"
  local ignore_file="$control_dir/.gitignore"
  local required=(
    "_bmad-output/lens-work/external-repos.yaml"
    "bmad.lens.release"
    ".gihub"
    ".github"
    "TargetProjects/lens/lens-governance"
  )

  if [[ ! -f "$ignore_file" ]]; then
    if $dry_run; then
      echo "[dry-run] create $ignore_file"
    else
      : > "$ignore_file"
    fi
  fi

  local entry
  for entry in "${required[@]}"; do
    if [[ -f "$ignore_file" ]] && grep -Fxq "$entry" "$ignore_file"; then
      continue
    fi
    if $dry_run; then
      echo "[dry-run] append to .gitignore: $entry"
    else
      printf '%s\n' "$entry" >> "$ignore_file"
    fi
  done
}

branch_of() {
  git -C "$1" symbolic-ref --short HEAD 2>/dev/null || echo "detached"
}

sha_of() {
  git -C "$1" rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

write_state_file() {
  local control_dir="$1"
  local release_dir="$2"
  local copilot_dir="$3"
  local governance_dir="$4"

  local state_dir="$control_dir/_bmad-output/lens-work"
  local state_file="$state_dir/external-repos.yaml"

  if $dry_run; then
    echo "[dry-run] write $state_file"
    return
  fi

  mkdir -p "$state_dir"

  cat > "$state_file" <<EOF
schema: 1
updated_utc: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
repos:
  release:
    path: "$release_dir"
    branch: "$(branch_of "$release_dir")"
    sha: "$(sha_of "$release_dir")"
    source: "$release_url"
  copilot:
    path: "$copilot_dir"
    branch: "$(branch_of "$copilot_dir")"
    sha: "$(sha_of "$copilot_dir")"
    source: "$copilot_url"
  governance:
    path: "$governance_dir"
    branch: "$(branch_of "$governance_dir")"
    sha: "$(sha_of "$governance_dir")"
    source: "$governance_url"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control)
      control_location="${2:-}"
      shift 2
      ;;
    --control-dir)
      control_dir_arg="${2:-}"
      shift 2
      ;;
    --control-branch)
      control_branch="${2:-}"
      shift 2
      ;;
    --release-url)
      release_url="${2:-}"
      shift 2
      ;;
    --release-branch)
      release_branch="${2:-}"
      shift 2
      ;;
    --copilot-url)
      copilot_url="${2:-}"
      shift 2
      ;;
    --copilot-branch)
      copilot_branch="${2:-}"
      shift 2
      ;;
    --governance-url)
      governance_url="${2:-}"
      shift 2
      ;;
    --governance-branch)
      governance_branch="${2:-}"
      shift 2
      ;;
    --yes)
      assume_yes=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

prompt_if_empty control_location "Control repo path or URL"
if [[ -z "$control_location" ]]; then
  echo "ERROR: --control is required." >&2
  exit 1
fi

control_dir=""
if is_git_url "$control_location"; then
  default_name="$(basename "$control_location")"
  default_name="${default_name%.git}"
  default_dir="$PWD/$default_name"
  prompt_if_empty control_dir_arg "Local control repo directory" "$default_dir"
  control_dir="$(normalize_path "$control_dir_arg")"

  if [[ -e "$control_dir" && ! -d "$control_dir/.git" ]]; then
    echo "ERROR: Control directory exists but is not a git repo: $control_dir" >&2
    exit 1
  fi

  if [[ -d "$control_dir/.git" ]]; then
    run git -C "$control_dir" remote set-url origin "$control_location"
    run git -C "$control_dir" fetch --prune origin
    run git -C "$control_dir" pull --ff-only origin
  else
    run mkdir -p "$(dirname "$control_dir")"
    run git clone "$control_location" "$control_dir"
  fi
else
  control_dir="$(normalize_path "$control_location")"
  if [[ ! -d "$control_dir" ]]; then
    echo "ERROR: Control repo path does not exist: $control_dir" >&2
    exit 1
  fi
  if [[ ! -d "$control_dir/.git" ]]; then
    echo "ERROR: Control path is not a git repo: $control_dir" >&2
    exit 1
  fi
  run git -C "$control_dir" fetch --prune origin || true
fi

if [[ -n "$control_branch" ]]; then
  if git -C "$control_dir" remote get-url origin >/dev/null 2>&1; then
    run git -C "$control_dir" fetch --prune origin
    if ! git -C "$control_dir" ls-remote --exit-code --heads origin "$control_branch" >/dev/null 2>&1; then
      echo "ERROR: Control branch '$control_branch' not found on origin." >&2
      exit 1
    fi
    run git -C "$control_dir" checkout -B "$control_branch" "origin/$control_branch"
  else
    if ! git -C "$control_dir" show-ref --verify --quiet "refs/heads/$control_branch"; then
      echo "ERROR: Control repo has no origin and local branch '$control_branch' does not exist." >&2
      exit 1
    fi
    run git -C "$control_dir" checkout "$control_branch"
  fi
fi

legacy_dir="$control_dir/.github"
copilot_dir="$control_dir/.gihub"
if [[ "$legacy_dir" != "$copilot_dir" && -e "$legacy_dir" ]]; then
  run rm -rf "$legacy_dir"
fi

release_dir="$control_dir/bmad.lens.release"
governance_dir="$control_dir/TargetProjects/lens/lens-governance"

ensure_repo_checkout "release" "$release_dir" "$release_url" "$release_branch"
ensure_repo_checkout "copilot" "$copilot_dir" "$copilot_url" "$copilot_branch"
ensure_repo_checkout "governance" "$governance_dir" "$governance_url" "$governance_branch"

ensure_control_gitignore "$control_dir"
write_state_file "$control_dir" "$release_dir" "$copilot_dir" "$governance_dir"

if ! $dry_run; then
  if [[ "$(branch_of "$release_dir")" != "$release_branch" ]]; then
    echo "ERROR: Release repo is not on expected branch '$release_branch'." >&2
    exit 1
  fi
  if [[ "$(branch_of "$copilot_dir")" != "$copilot_branch" ]]; then
    echo "ERROR: Copilot repo is not on expected branch '$copilot_branch'." >&2
    exit 1
  fi
  if [[ "$(branch_of "$governance_dir")" != "$governance_branch" ]]; then
    echo "ERROR: Governance repo is not on expected branch '$governance_branch'." >&2
    exit 1
  fi
fi

echo "Onboarding complete"
echo "- control:    $control_dir (${control_branch:-current})"
echo "- release:    $release_dir @ $(branch_of "$release_dir")"
echo "- copilot:    $copilot_dir @ $(branch_of "$copilot_dir")"
echo "- governance: $governance_dir @ $(branch_of "$governance_dir")"
