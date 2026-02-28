# bmad.lens.setup

Bootstrap utilities for onboarding a BMAD LENS control repository with the external repos:

- `bmad.lens.release`
- `bmad.lens.copilot` (cloned into `.gihub`)
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
- normalize remotes when folders already exist,
- remove legacy `controlRepo/.github` when present,
- ensure control `.gitignore` includes external-repo exclusions,
- write `_bmad-output/lens-work/external-repos.yaml` state.

## Defaults

- Release repo: `https://github.com/crisweber2600/bmad.lens.release.git` @ `release/2.0.0`
- Copilot repo: `https://github.com/crisweber2600/bmad.lens.copilot.git` @ `main`
- Governance repo: `https://github.com/crisweber2600/bmad.lens.governance.git` @ `main`

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
  -ControlBranch "northstar"
```

## Notes

- For existing folders, the script requires them to already be git repos (`.git` present).
- If an expected branch is missing on origin, bootstrap fails fast.
- Use `--dry-run` / `-DryRun` to preview actions.
