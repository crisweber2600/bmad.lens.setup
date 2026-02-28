param(
  [Parameter(Mandatory = $false)]
  [string]$ControlLocation,

  [Parameter(Mandatory = $false)]
  [string]$ControlDirectory,

  [Parameter(Mandatory = $false)]
  [string]$ControlBranch,

  [Parameter(Mandatory = $false)]
  [string]$ReleaseRepoUrl = "https://github.com/crisweber2600/bmad.lens.release.git",

  [Parameter(Mandatory = $false)]
  [string]$ReleaseBranch = "release/2.0.0",

  [Parameter(Mandatory = $false)]
  [string]$CopilotRepoUrl = "https://github.com/crisweber2600/bmad.lens.copilot.git",

  [Parameter(Mandatory = $false)]
  [string]$CopilotBranch = "main",

  [Parameter(Mandatory = $false)]
  [string]$GovernanceRepoUrl = "https://github.com/crisweber2600/bmad.lens.governance.git",

  [Parameter(Mandatory = $false)]
  [string]$GovernanceBranch = "main",

  [Parameter(Mandatory = $false)]
  [string]$GovernanceRepoName,

  [Parameter(Mandatory = $false)]
  [string]$GovernanceOwner,

  [switch]$Yes,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$isNewControlRepo = $false

function Test-IsGitUrl {
  param([string]$Value)
  return $Value -match '^(https://|http://|ssh://|git@)'
}

function Get-GitHubOwnerFromUrl {
  param([string]$RepoUrl)

  if ($RepoUrl -match '^https?://github\.com/([^/]+)/[^/]+(\.git)?$') {
    return $Matches[1]
  }

  if ($RepoUrl -match '^git@github\.com:([^/]+)/[^/]+(\.git)?$') {
    return $Matches[1]
  }

  return ''
}

function Test-GhReady {
  $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $ghCmd) { return $false }
  gh auth status *> $null
  return ($LASTEXITCODE -eq 0)
}

function Invoke-Step {
  param([scriptblock]$Script, [string]$Preview)
  if ($DryRun) {
    Write-Host "[dry-run] $Preview"
  } else {
    & $Script
  }
}

function Ensure-GovernanceRepoForNewControl {
  param([string]$ControlRepo)

  if (-not $GovernanceRepoName) {
    $defaultName = [System.IO.Path]::GetFileNameWithoutExtension($GovernanceRepoUrl)
    if ($Yes) {
      $GovernanceRepoName = $defaultName
    } else {
      $entered = Read-Host "Governance repo name [$defaultName]"
      $GovernanceRepoName = if ($entered) { $entered } else { $defaultName }
    }
  }

  if (-not $GovernanceRepoName) {
    throw 'Governance repo name is required for new repo onboarding.'
  }

  if (-not $GovernanceOwner) {
    $originUrl = ''
    try { $originUrl = (git -C $ControlRepo remote get-url origin 2>$null).Trim() } catch {}
    $GovernanceOwner = Get-GitHubOwnerFromUrl $originUrl
  }

  if (-not $GovernanceOwner) {
    $GovernanceOwner = Get-GitHubOwnerFromUrl $GovernanceRepoUrl
  }

  if (-not $GovernanceOwner) {
    throw 'Unable to determine governance repo owner. Pass -GovernanceOwner.'
  }

  $script:GovernanceRepoUrl = "https://github.com/$GovernanceOwner/$GovernanceRepoName.git"

  if (Test-GhReady) {
    gh api "repos/$GovernanceOwner/$GovernanceRepoName" *> $null
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Using existing governance repo: $GovernanceOwner/$GovernanceRepoName"
      return
    }

    if ($DryRun) {
      Write-Host "[dry-run] create private repo: $GovernanceOwner/$GovernanceRepoName"
      return
    }

    $currentUser = ''
    try { $currentUser = (gh api user -q .login 2>$null).Trim() } catch {}

    if ($GovernanceOwner -eq $currentUser) {
      gh api -X POST user/repos -f name="$GovernanceRepoName" -F private=true -F auto_init=true | Out-Null
    } else {
      gh api -X POST "orgs/$GovernanceOwner/repos" -f name="$GovernanceRepoName" -F private=true -F auto_init=true | Out-Null
    }

    Write-Host "Created private governance repo: $GovernanceOwner/$GovernanceRepoName"
    return
  }

  git ls-remote $GovernanceRepoUrl HEAD *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Using existing governance repo: $GovernanceOwner/$GovernanceRepoName"
    return
  }

  throw "Governance repo '$GovernanceOwner/$GovernanceRepoName' does not exist, and gh auth is unavailable to create it."
}

function Get-RepoBranch {
  param([string]$Path)
  $out = git -C $Path symbolic-ref --short HEAD 2>$null
  if ($LASTEXITCODE -eq 0 -and $out) { return $out.Trim() }
  return 'detached'
}

function Get-RepoSha {
  param([string]$Path)
  $out = git -C $Path rev-parse --short HEAD 2>$null
  if ($LASTEXITCODE -eq 0 -and $out) { return $out.Trim() }
  return 'unknown'
}

function Ensure-RepoCheckout {
  param(
    [string]$Label,
    [string]$Path,
    [string]$RepoUrl,
    [string]$Branch
  )

  if ((Test-Path $Path) -and -not (Test-Path (Join-Path $Path '.git'))) {
    throw "$Label path exists but is not a git repository: $Path"
  }

  if (Test-Path (Join-Path $Path '.git')) {
    Invoke-Step -Preview "git -C $Path remote set-url origin $RepoUrl" -Script { git -C $Path remote set-url origin $RepoUrl | Out-Null }
    Invoke-Step -Preview "git -C $Path fetch --prune origin" -Script { git -C $Path fetch --prune origin | Out-Null }
  }
  else {
    Invoke-Step -Preview "create directory $(Split-Path -Parent $Path)" -Script { New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null }
    Invoke-Step -Preview "git clone $RepoUrl $Path" -Script { git clone $RepoUrl $Path | Out-Null }
    Invoke-Step -Preview "git -C $Path fetch --prune origin" -Script { git -C $Path fetch --prune origin | Out-Null }
  }

  git -C $Path ls-remote --exit-code --heads origin $Branch | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Branch '$Branch' not found on '$RepoUrl' for $Label"
  }

  Invoke-Step -Preview "git -C $Path checkout -B $Branch origin/$Branch" -Script { git -C $Path checkout -B $Branch "origin/$Branch" | Out-Null }
  Invoke-Step -Preview "git -C $Path pull --ff-only origin $Branch" -Script { git -C $Path pull --ff-only origin $Branch | Out-Null }
}

function Ensure-ControlGitIgnore {
  param([string]$ControlRepo)

  $ignoreFile = Join-Path $ControlRepo '.gitignore'
  $required = @(
    '_bmad-output/lens-work/external-repos.yaml',
    'bmad.lens.release',
    '.github',
    'TargetProjects/lens/lens-governance'
  )

  if (-not (Test-Path $ignoreFile)) {
    Invoke-Step -Preview "create $ignoreFile" -Script { New-Item -ItemType File -Path $ignoreFile -Force | Out-Null }
  }

  $existing = @()
  if (Test-Path $ignoreFile) {
    $existing = Get-Content $ignoreFile
  }

  foreach ($entry in $required) {
    if ($existing -contains $entry) {
      continue
    }

    if ($DryRun) {
      Write-Host "[dry-run] append to .gitignore: $entry"
    } else {
      Add-Content -Path $ignoreFile -Value $entry
      $existing += $entry
    }
  }

  if ($existing -contains '.gihub') {
    if ($DryRun) {
      Write-Host '[dry-run] remove legacy .gitignore entry: .gihub'
    } else {
      $filtered = $existing | Where-Object { $_ -ne '.gihub' }
      Set-Content -Path $ignoreFile -Value ($filtered -join "`n") -NoNewline
    }
  }
}

function Write-SelfOnboardingScripts {
  param([string]$ControlRepo)

  $scriptsDir = Join-Path $ControlRepo 'scripts'
  $onboardSh = Join-Path $scriptsDir 'onboard-workspace.sh'
  $onboardPs1 = Join-Path $scriptsDir 'onboard-workspace.ps1'

  if ($DryRun) {
    Write-Host "[dry-run] write $onboardSh"
    Write-Host "[dry-run] write $onboardPs1"
    return
  }

  New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

  $shTemplate = @'
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
'@

  $psTemplate = @'
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
'@

  $shContent = $shTemplate.Replace('__RELEASE_URL__', $ReleaseRepoUrl).Replace('__RELEASE_BRANCH__', $ReleaseBranch).Replace('__COPILOT_URL__', $CopilotRepoUrl).Replace('__COPILOT_BRANCH__', $CopilotBranch).Replace('__GOVERNANCE_URL__', $GovernanceRepoUrl).Replace('__GOVERNANCE_BRANCH__', $GovernanceBranch)
  $psContent = $psTemplate.Replace('__RELEASE_URL__', $ReleaseRepoUrl).Replace('__RELEASE_BRANCH__', $ReleaseBranch).Replace('__COPILOT_URL__', $CopilotRepoUrl).Replace('__COPILOT_BRANCH__', $CopilotBranch).Replace('__GOVERNANCE_URL__', $GovernanceRepoUrl).Replace('__GOVERNANCE_BRANCH__', $GovernanceBranch)

  Set-Content -Path $onboardSh -Value $shContent -NoNewline
  Set-Content -Path $onboardPs1 -Value $psContent -NoNewline
}

function Commit-ControlSetup {
  param([string]$ControlRepo)

  if ($DryRun) {
    Write-Host "[dry-run] git -C $ControlRepo add .gitignore scripts/onboard-workspace.sh scripts/onboard-workspace.ps1"
    Write-Host "[dry-run] git -C $ControlRepo commit -m Add self-onboarding scripts for new joiners"
    Write-Host "[dry-run] git -C $ControlRepo push origin <current-branch>"
    return
  }

  git -C $ControlRepo rev-parse --is-inside-work-tree | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "WARN: $ControlRepo is not a git repo; skipping commit/push of onboarding scripts."
    return
  }

  git -C $ControlRepo add .gitignore scripts/onboard-workspace.sh scripts/onboard-workspace.ps1 | Out-Null
  git -C $ControlRepo diff --cached --quiet
  if ($LASTEXITCODE -eq 0) {
    Write-Host 'No control setup file changes to commit.'
    return
  }

  git -C $ControlRepo commit -m 'Add self-onboarding scripts for new joiners' | Out-Null

  $hasOrigin = $true
  try {
    git -C $ControlRepo remote get-url origin | Out-Null
  } catch {
    $hasOrigin = $false
  }

  if (-not $hasOrigin) {
    Write-Host 'WARN: Control repo has no origin remote; skipping push.'
    return
  }

  $currentBranch = (Get-RepoBranch $ControlRepo)
  if ([string]::IsNullOrWhiteSpace($currentBranch) -or $currentBranch -eq 'detached') {
    throw 'Unable to determine current control repo branch for push.'
  }

  git -C $ControlRepo push origin $currentBranch | Out-Null
}

function Write-StateFile {
  param(
    [string]$ControlRepo,
    [string]$ReleasePath,
    [string]$CopilotPath,
    [string]$GovernancePath
  )

  $stateDir = Join-Path $ControlRepo '_bmad-output/lens-work'
  $stateFile = Join-Path $stateDir 'external-repos.yaml'

  if ($DryRun) {
    Write-Host "[dry-run] write $stateFile"
    return
  }

  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

  $updatedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $yaml = @"
schema: 1
updated_utc: "$updatedUtc"
repos:
  release:
    path: "$ReleasePath"
    branch: "$(Get-RepoBranch $ReleasePath)"
    sha: "$(Get-RepoSha $ReleasePath)"
    source: "$ReleaseRepoUrl"
  copilot:
    path: "$CopilotPath"
    branch: "$(Get-RepoBranch $CopilotPath)"
    sha: "$(Get-RepoSha $CopilotPath)"
    source: "$CopilotRepoUrl"
  governance:
    path: "$GovernancePath"
    branch: "$(Get-RepoBranch $GovernancePath)"
    sha: "$(Get-RepoSha $GovernancePath)"
    source: "$GovernanceRepoUrl"
"@

  Set-Content -Path $stateFile -Value $yaml -NoNewline
}

if (-not $ControlLocation) {
  if ($Yes) {
    throw "-ControlLocation is required when -Yes is used."
  }
  $ControlLocation = Read-Host 'Control repo path or URL'
}

if (-not $ControlLocation) {
  throw 'Control location is required.'
}

$controlRepo = $null
if (Test-IsGitUrl $ControlLocation) {
  $repoName = [System.IO.Path]::GetFileNameWithoutExtension($ControlLocation)
  $defaultDir = Join-Path (Get-Location) $repoName

  if (-not $ControlDirectory) {
    if ($Yes) {
      $ControlDirectory = $defaultDir
    } else {
      $entered = Read-Host "Local control repo directory [$defaultDir]"
      $ControlDirectory = if ($entered) { $entered } else { $defaultDir }
    }
  }

  $controlRepo = $ControlDirectory

  if ((Test-Path $controlRepo) -and -not (Test-Path (Join-Path $controlRepo '.git'))) {
    throw "Control directory exists but is not a git repo: $controlRepo"
  }

  if (Test-Path (Join-Path $controlRepo '.git')) {
    Invoke-Step -Preview "git -C $controlRepo remote set-url origin $ControlLocation" -Script { git -C $controlRepo remote set-url origin $ControlLocation | Out-Null }
    Invoke-Step -Preview "git -C $controlRepo fetch --prune origin" -Script { git -C $controlRepo fetch --prune origin | Out-Null }
    Invoke-Step -Preview "git -C $controlRepo pull --ff-only origin" -Script { git -C $controlRepo pull --ff-only origin | Out-Null }
  }
  else {
    $isNewControlRepo = $true
    Invoke-Step -Preview "create directory $(Split-Path -Parent $controlRepo)" -Script { New-Item -ItemType Directory -Path (Split-Path -Parent $controlRepo) -Force | Out-Null }
    Invoke-Step -Preview "git clone $ControlLocation $controlRepo" -Script { git clone $ControlLocation $controlRepo | Out-Null }
  }
}
else {
  $controlRepo = $ControlLocation
  if (-not (Test-Path $controlRepo)) {
    throw "Control repo path does not exist: $controlRepo"
  }
  if (-not (Test-Path (Join-Path $controlRepo '.git'))) {
    throw "Control path is not a git repo: $controlRepo"
  }

  try { Invoke-Step -Preview "git -C $controlRepo fetch --prune origin" -Script { git -C $controlRepo fetch --prune origin | Out-Null } } catch {}
}

if ($ControlBranch) {
  $hasOrigin = $true
  try {
    git -C $controlRepo remote get-url origin | Out-Null
  }
  catch {
    $hasOrigin = $false
  }

  if ($hasOrigin) {
    Invoke-Step -Preview "git -C $controlRepo fetch --prune origin" -Script { git -C $controlRepo fetch --prune origin | Out-Null }
    git -C $controlRepo ls-remote --exit-code --heads origin $ControlBranch | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Control branch '$ControlBranch' not found on origin."
    }
    Invoke-Step -Preview "git -C $controlRepo checkout -B $ControlBranch origin/$ControlBranch" -Script { git -C $controlRepo checkout -B $ControlBranch "origin/$ControlBranch" | Out-Null }
  }
  else {
    git -C $controlRepo show-ref --verify --quiet "refs/heads/$ControlBranch"
    if ($LASTEXITCODE -ne 0) {
      throw "Control repo has no origin and local branch '$ControlBranch' does not exist."
    }
    Invoke-Step -Preview "git -C $controlRepo checkout $ControlBranch" -Script { git -C $controlRepo checkout $ControlBranch | Out-Null }
  }
}

$legacyDir = Join-Path $controlRepo '.gihub'
$copilotDir = Join-Path $controlRepo '.github'
if ((Test-Path (Join-Path $legacyDir '.git')) -and -not (Test-Path $copilotDir)) {
  Invoke-Step -Preview "move $legacyDir to $copilotDir" -Script { Move-Item -Path $legacyDir -Destination $copilotDir }
}
elseif ((Test-Path $legacyDir) -and ($legacyDir -ne $copilotDir)) {
  Invoke-Step -Preview "remove $legacyDir" -Script { Remove-Item $legacyDir -Recurse -Force }
}

$releaseDir = Join-Path $controlRepo 'bmad.lens.release'
$governanceDir = Join-Path $controlRepo 'TargetProjects/lens/lens-governance'

if ($isNewControlRepo) {
  Ensure-GovernanceRepoForNewControl -ControlRepo $controlRepo
}

Ensure-RepoCheckout -Label 'release' -Path $releaseDir -RepoUrl $ReleaseRepoUrl -Branch $ReleaseBranch
Ensure-RepoCheckout -Label 'copilot' -Path $copilotDir -RepoUrl $CopilotRepoUrl -Branch $CopilotBranch
Ensure-RepoCheckout -Label 'governance' -Path $governanceDir -RepoUrl $GovernanceRepoUrl -Branch $GovernanceBranch

Ensure-ControlGitIgnore -ControlRepo $controlRepo
Write-StateFile -ControlRepo $controlRepo -ReleasePath $releaseDir -CopilotPath $copilotDir -GovernancePath $governanceDir
Write-SelfOnboardingScripts -ControlRepo $controlRepo
Commit-ControlSetup -ControlRepo $controlRepo

if (-not $DryRun) {
  if ((Get-RepoBranch $releaseDir) -ne $ReleaseBranch) {
    throw "Release repo is not on expected branch '$ReleaseBranch'."
  }
  if ((Get-RepoBranch $copilotDir) -ne $CopilotBranch) {
    throw "Copilot repo is not on expected branch '$CopilotBranch'."
  }
  if ((Get-RepoBranch $governanceDir) -ne $GovernanceBranch) {
    throw "Governance repo is not on expected branch '$GovernanceBranch'."
  }
}

$controlBranchDisplay = 'current'
if (-not [string]::IsNullOrWhiteSpace($ControlBranch)) {
  $controlBranchDisplay = $ControlBranch
}

Write-Host 'Onboarding complete'
Write-Host "- control:    $controlRepo ($controlBranchDisplay)"
Write-Host "- release:    $releaseDir @ $(Get-RepoBranch $releaseDir)"
Write-Host "- copilot:    $copilotDir @ $(Get-RepoBranch $copilotDir)"
Write-Host "- governance: $governanceDir @ $(Get-RepoBranch $governanceDir)"
