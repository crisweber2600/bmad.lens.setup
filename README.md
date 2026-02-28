# bmad.lens.setup

Bootstrap utilities for onboarding a BMAD LENS control repository with the external repos:

- `bmad.lens.release`
- `bmad.lens.copilot` (cloned into `.github`)
- `bmad.lens.governance` (cloned into `TargetProjects/lens/lens-governance`)

The bootstrap scripts support providing the control repo as either:

- a **local drive path** (for example: `D:\NorthStarET.BMAD`), or
- a **git URL** (for example: `https://github.com/crisweber2600/NorthStarET.BMAD.git`).

## Scripts

- `scripts/bootstrap-control.sh`
- `scripts/bootstrap-control.ps1`

Both scripts:

- prompt for control repo location when not provided,
- clone or update the external repos,
- verify expected branches exist remotely and check them out,
- resolve branches by mode when branch args are omitted (`stable` = default branch, `beta` = latest commit branch),
- normalize remotes when folders already exist,
- migrate legacy `controlRepo/.gihub` to `controlRepo/.github` when present,
- ensure control `.gitignore` includes external-repo exclusions,
- when onboarding a brand-new control repo, ask for governance repo name and use it (owner defaults from control repo owner),
- clone the governance repo if it exists, or create it as private (via authenticated GitHub CLI) when missing,
- write `_bmad-output/lens-work/external-repos.yaml` state,
- generate `scripts/onboard-workspace.sh` and `scripts/onboard-workspace.ps1` inside the target control repo,
- commit and push those onboarding files to the target control repo branch.

## Defaults

- Mode: `stable`
- Release repo: `https://github.com/crisweber2600/bmad.lens.release.git`
- Copilot repo: `https://github.com/crisweber2600/bmad.lens.copilot.git`
- Governance repo: `https://github.com/crisweber2600/bmad.lens.governance.git`

## Usage

### Bash (Git Bash)

```bash
bash scripts/bootstrap-control.sh \
  --control "D:\\NorthStarET.BMAD" \
  --control-branch northstar
```

```bash
bash scripts/bootstrap-control.sh \
  --control "https://github.com/crisweber2600/NorthStarET.BMAD.git" \
  --control-dir "/d/NorthStarET.BMAD" \
  --mode beta \
  --control-branch northstar
```

### PowerShell

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-control.ps1 `
  -ControlLocation "D:\NorthStarET.BMAD" `
  -ControlBranch "northstar"
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-control.ps1 `
  -ControlLocation "https://github.com/crisweber2600/NorthStarET.BMAD.git" `
  -ControlDirectory "D:\NorthStarET.BMAD" `
  -Mode "beta" `
  -ControlBranch "northstar"
```

## Notes

- For existing folders, the script requires them to already be git repos (`.git` present).
- If an expected branch is missing on origin, bootstrap fails fast.
- Use `--dry-run` / `-DryRun` to preview actions.
- Use `--mode stable|beta` (`-Mode stable|beta`) when you want automatic branch selection.
- For new control repo onboarding, pass `--governance-repo-name` / `-GovernanceRepoName` to avoid prompts.
- Private governance repo auto-create requires authenticated `gh` CLI access.
- New joiners can clone the control repo and run `scripts/onboard-workspace.sh` or `scripts/onboard-workspace.ps1` to set up external repos locally.
