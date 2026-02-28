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
  [string]$ReleaseBranch = "5.0",

  [Parameter(Mandatory = $false)]
  [string]$CopilotRepoUrl = "https://github.com/crisweber2600/bmad.lens.copilot.git",

  [Parameter(Mandatory = $false)]
  [string]$CopilotBranch = "main",

  [Parameter(Mandatory = $false)]
  [string]$GovernanceRepoUrl = "https://github.com/crisweber2600/bmad.lens.governance.git",

  [Parameter(Mandatory = $false)]
  [string]$GovernanceBranch = "main",

  [switch]$Yes,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Test-IsGitUrl {
  param([string]$Value)
  return $Value -match '^(https://|http://|ssh://|git@)'
}

function Invoke-Step {
  param([scriptblock]$Script, [string]$Preview)
  if ($DryRun) {
    Write-Host "[dry-run] $Preview"
  } else {
    & $Script
  }
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
    '.gihub',
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

$legacyDir = Join-Path $controlRepo '.github'
$copilotDir = Join-Path $controlRepo '.gihub'
if ((Test-Path $legacyDir) -and ($legacyDir -ne $copilotDir)) {
  Invoke-Step -Preview "remove $legacyDir" -Script { Remove-Item $legacyDir -Recurse -Force }
}

$releaseDir = Join-Path $controlRepo 'bmad.lens.release'
$governanceDir = Join-Path $controlRepo 'TargetProjects/lens/lens-governance'

Ensure-RepoCheckout -Label 'release' -Path $releaseDir -RepoUrl $ReleaseRepoUrl -Branch $ReleaseBranch
Ensure-RepoCheckout -Label 'copilot' -Path $copilotDir -RepoUrl $CopilotRepoUrl -Branch $CopilotBranch
Ensure-RepoCheckout -Label 'governance' -Path $governanceDir -RepoUrl $GovernanceRepoUrl -Branch $GovernanceBranch

Ensure-ControlGitIgnore -ControlRepo $controlRepo
Write-StateFile -ControlRepo $controlRepo -ReleasePath $releaseDir -CopilotPath $copilotDir -GovernancePath $governanceDir

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

Write-Host 'Onboarding complete'
Write-Host "- control:    $controlRepo ($([string]::IsNullOrWhiteSpace($ControlBranch) ? 'current' : $ControlBranch))"
Write-Host "- release:    $releaseDir @ $(Get-RepoBranch $releaseDir)"
Write-Host "- copilot:    $copilotDir @ $(Get-RepoBranch $copilotDir)"
Write-Host "- governance: $governanceDir @ $(Get-RepoBranch $governanceDir)"
