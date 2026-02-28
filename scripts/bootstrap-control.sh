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

  if [[ -f "$ignore_file" ]] && grep -Fxq ".gihub" "$ignore_file"; then
    if $dry_run; then
      echo "[dry-run] remove legacy .gitignore entry: .gihub"
    else
      sed -i '/^\.gihub$/d' "$ignore_file"
    fi
  fi
}

esc_sed_replacement() {
  printf '%s' "$1" | sed 's/[|&]/\\&/g'
}

write_self_onboarding_scripts() {
  local control_dir="$1"
  local scripts_dir="$control_dir/scripts"
  local onboard_sh="$scripts_dir/onboard-workspace.sh"
  local onboard_ps1="$scripts_dir/onboard-workspace.ps1"

  if $dry_run; then
    echo "[dry-run] write $onboard_sh"
    echo "[dry-run] write $onboard_ps1"
    return
  fi

  mkdir -p "$scripts_dir"

  cat > "$onboard_sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

control_dir="$(cd "$(dirname "$0")/.." && pwd)"
setup_repo_url="https://github.com/crisweber2600/bmad.lens.setup.git"
setup_branch="main"
setup_dir="${TMPDIR:-/tmp}/bmad.lens.setup"

release_url_default="__RELEASE_URL__"
release_branch_default="__RELEASE_BRANCH__"
copilot_url_default="__COPILOT_URL__"
copilot_branch_default="__COPILOT_BRANCH__"
governance_url_default="__GOVERNANCE_URL__"
governance_branch_default="__GOVERNANCE_BRANCH__"

if [[ -d "$setup_dir/.git" ]]; then
  git -C "$setup_dir" remote set-url origin "$setup_repo_url"
  git -C "$setup_dir" fetch --prune origin
  if git -C "$setup_dir" ls-remote --exit-code --heads origin "$setup_branch" >/dev/null 2>&1; then
    git -C "$setup_dir" checkout -B "$setup_branch" "origin/$setup_branch"
    git -C "$setup_dir" pull --ff-only origin "$setup_branch"
  fi
else
  rm -rf "$setup_dir"
  git clone "$setup_repo_url" "$setup_dir"
  if git -C "$setup_dir" ls-remote --exit-code --heads origin "$setup_branch" >/dev/null 2>&1; then
    git -C "$setup_dir" checkout -B "$setup_branch" "origin/$setup_branch"
  fi
fi

bash "$setup_dir/scripts/bootstrap-control.sh" \
  --control "$control_dir" \
  --release-url "$release_url_default" \
  --release-branch "$release_branch_default" \
  --copilot-url "$copilot_url_default" \
  --copilot-branch "$copilot_branch_default" \
  --governance-url "$governance_url_default" \
  --governance-branch "$governance_branch_default" \
  "$@"
EOF

  cat > "$onboard_ps1" <<'EOF'
param(
  [string]$SetupRepoUrl = "https://github.com/crisweber2600/bmad.lens.setup.git",
  [string]$SetupBranch = "main"
)

$ErrorActionPreference = 'Stop'

$controlRepo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$setupDir = Join-Path ([System.IO.Path]::GetTempPath()) "bmad.lens.setup"

$releaseUrl = "__RELEASE_URL__"
$releaseBranch = "__RELEASE_BRANCH__"
$copilotUrl = "__COPILOT_URL__"
$copilotBranch = "__COPILOT_BRANCH__"
$governanceUrl = "__GOVERNANCE_URL__"
$governanceBranch = "__GOVERNANCE_BRANCH__"

if (Test-Path (Join-Path $setupDir '.git')) {
  git -C $setupDir remote set-url origin $SetupRepoUrl | Out-Null
  git -C $setupDir fetch --prune origin | Out-Null
  try {
    git -C $setupDir ls-remote --exit-code --heads origin $SetupBranch | Out-Null
    git -C $setupDir checkout -B $SetupBranch "origin/$SetupBranch" | Out-Null
    git -C $setupDir pull --ff-only origin $SetupBranch | Out-Null
  } catch {}
}
else {
  if (Test-Path $setupDir) { Remove-Item $setupDir -Recurse -Force }
  git clone $SetupRepoUrl $setupDir | Out-Null
  try {
    git -C $setupDir ls-remote --exit-code --heads origin $SetupBranch | Out-Null
    git -C $setupDir checkout -B $SetupBranch "origin/$SetupBranch" | Out-Null
  } catch {}
}

$bootstrapScript = Join-Path $setupDir 'scripts/bootstrap-control.ps1'
& $bootstrapScript `
  -ControlLocation $controlRepo `
  -ReleaseRepoUrl $releaseUrl `
  -ReleaseBranch $releaseBranch `
  -CopilotRepoUrl $copilotUrl `
  -CopilotBranch $copilotBranch `
  -GovernanceRepoUrl $governanceUrl `
  -GovernanceBranch $governanceBranch
EOF

  local release_url_esc
  local release_branch_esc
  local copilot_url_esc
  local copilot_branch_esc
  local governance_url_esc
  local governance_branch_esc

  release_url_esc="$(esc_sed_replacement "$release_url")"
  release_branch_esc="$(esc_sed_replacement "$release_branch")"
  copilot_url_esc="$(esc_sed_replacement "$copilot_url")"
  copilot_branch_esc="$(esc_sed_replacement "$copilot_branch")"
  governance_url_esc="$(esc_sed_replacement "$governance_url")"
  governance_branch_esc="$(esc_sed_replacement "$governance_branch")"

  sed -i \
    -e "s|__RELEASE_URL__|$release_url_esc|g" \
    -e "s|__RELEASE_BRANCH__|$release_branch_esc|g" \
    -e "s|__COPILOT_URL__|$copilot_url_esc|g" \
    -e "s|__COPILOT_BRANCH__|$copilot_branch_esc|g" \
    -e "s|__GOVERNANCE_URL__|$governance_url_esc|g" \
    -e "s|__GOVERNANCE_BRANCH__|$governance_branch_esc|g" \
    "$onboard_sh" "$onboard_ps1"

  chmod +x "$onboard_sh"
}

commit_and_push_control_setup() {
  local control_dir="$1"

  if $dry_run; then
    echo "[dry-run] git -C $control_dir add .gitignore scripts/onboard-workspace.sh scripts/onboard-workspace.ps1"
    echo "[dry-run] git -C $control_dir commit -m Add self-onboarding scripts for new joiners"
    echo "[dry-run] git -C $control_dir push origin <current-branch>"
    return
  fi

  if ! git -C "$control_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "WARN: $control_dir is not a git repo; skipping commit/push of onboarding scripts."
    return
  fi

  git -C "$control_dir" add .gitignore scripts/onboard-workspace.sh scripts/onboard-workspace.ps1

  if git -C "$control_dir" diff --cached --quiet; then
    echo "No control setup file changes to commit."
    return
  fi

  git -C "$control_dir" commit -m "Add self-onboarding scripts for new joiners"

  if git -C "$control_dir" remote get-url origin >/dev/null 2>&1; then
    local current_branch
    current_branch="$(git -C "$control_dir" symbolic-ref --short HEAD 2>/dev/null || true)"
    if [[ -z "$current_branch" ]]; then
      echo "ERROR: Unable to determine current control repo branch for push." >&2
      exit 1
    fi
    git -C "$control_dir" push origin "$current_branch"
  else
    echo "WARN: Control repo has no origin remote; skipping push."
  fi
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

legacy_dir="$control_dir/.gihub"
copilot_dir="$control_dir/.github"
if [[ -d "$legacy_dir/.git" && ! -e "$copilot_dir" ]]; then
  run mv "$legacy_dir" "$copilot_dir"
elif [[ "$legacy_dir" != "$copilot_dir" && -e "$legacy_dir" ]]; then
  run rm -rf "$legacy_dir"
fi

release_dir="$control_dir/bmad.lens.release"
governance_dir="$control_dir/TargetProjects/lens/lens-governance"

ensure_repo_checkout "release" "$release_dir" "$release_url" "$release_branch"
ensure_repo_checkout "copilot" "$copilot_dir" "$copilot_url" "$copilot_branch"
ensure_repo_checkout "governance" "$governance_dir" "$governance_url" "$governance_branch"

ensure_control_gitignore "$control_dir"
write_state_file "$control_dir" "$release_dir" "$copilot_dir" "$governance_dir"
write_self_onboarding_scripts "$control_dir"
commit_and_push_control_setup "$control_dir"

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
