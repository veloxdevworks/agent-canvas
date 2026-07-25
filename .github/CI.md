# CI notes (cost-aware)

Linux jobs stay on GitHub-hosted `ubuntu-latest`. macOS jobs should use a **self-hosted**
Mac runner when available (avoids expensive `macos-14` minutes).

## Workflows

| Workflow | When | Runner | Purpose |
|----------|------|--------|---------|
| **CI** (`ci.yml`) | PR / push to `main` (skips pure doc changes) | `ubuntu-latest` | `fmt` · `clippy` · `test` · release-build MCP |
| **macOS** (`macos.yml`) | **Manual** by default; PR/push if `ENABLE_MACOS_CI` | `MACOS_RUNS_ON` or `macos-14` | XcodeGen + unsigned `xcodebuild` |
| **Release** (`release.yml`) | Tag `v*.*.*` or manual | Linux always; macOS optional | GitHub Release + artifacts |

## Repo variables

Settings → Secrets and variables → Actions → **Variables**  
(or `gh variable set NAME --body '…' --repo veloxdevworks/agent-canvas`)

| Variable | Effect |
|----------|--------|
| `CI_DISABLED=true` | Skip automatic Linux CI jobs |
| `ENABLE_MACOS_CI=true` | Run macOS workflow on PR/push (paths under `platforms/macos/`) |
| `ENABLE_MACOS_RELEASE=true` | Build unsigned `.app` zip on version tags |
| `MACOS_RUNS_ON` | **JSON array of runner labels** (required for self-hosted) |

### Targeting the self-hosted MacBook

GitHub matches **all** labels in the array. Default self-hosted Mac install usually has:

```text
self-hosted
macOS
ARM64          # or X64 on Intel
```

Set (adjust labels to match **Settings → Actions → Runners** on the repo or org):

```bash
gh variable set MACOS_RUNS_ON --repo veloxdevworks/agent-canvas \
  --body '["self-hosted","macOS","ARM64"]'
```

Optional: turn on automatic macOS builds for Swift changes:

```bash
gh variable set ENABLE_MACOS_CI --repo veloxdevworks/agent-canvas --body true
```

If `MACOS_RUNS_ON` is unset, jobs fall back to GitHub-hosted `macos-14` (paid).

### Runner must be visible to this repo

| Where you registered the runner | Check |
|----------------------------------|--------|
| **This repository** | Repo → Settings → Actions → Runners — lists the Mac, status **Idle** |
| **Organization** (this project) | Org → Settings → Actions → Runners — see below |

#### Org-level runners (veloxdevworks)

Repo APIs only list **repo-scoped** runners (`total_count: 0` is normal when the Mac is org-wide). Org runners still work **if the runner group allows this repo**.

1. Open [github.com/organizations/veloxdevworks/settings/actions/runners](https://github.com/organizations/veloxdevworks/settings/actions/runners)  
2. Confirm the MacBook is **Idle** (green). Note its **labels** (must match `MACOS_RUNS_ON`).  
3. Open the **runner group** that contains it (often **Default**).  
4. Under **Repository access**:
   - **All repositories**, or  
   - **Selected repositories** → include **`agent-canvas`**  
5. Under **Workflow access** / **Allow public repositories** (wording varies): if `agent-canvas` is **public**, the group must allow **public** repos. Many defaults only allow private — that’s a common “Waiting for a runner” trap.  
6. Optional: Workflow permissions → ensure self-hosted runners aren’t restricted in org Actions policy.

Then:

```bash
gh workflow run macos.yml --repo veloxdevworks/agent-canvas
gh run list --repo veloxdevworks/agent-canvas --workflow=macos.yml --limit 3
```

Job state **in_progress** on your Mac = wired correctly. **Queued / Waiting for a runner** = labels or group access.

### Self-hosted machine checklist

- [ ] Xcode installed (app, not only CLT)
- [ ] `brew` available; first job may `brew install xcodegen` if missing
- [ ] Passwordless `sudo` for `xcode-select` **or** Xcode path already selected
- [ ] Runner app running (or LaunchAgent so it survives reboot)
- [ ] Enough disk for DerivedData under `build/ci-macos`

## Releasing

```bash
# 1. Update CHANGELOG.md [Unreleased] → [x.y.z]
# 2. Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in platforms/macos/project.yml
git tag v0.2.0
git push origin v0.2.0
```

Creates a GitHub Release with auto notes + Linux `agent-canvas-mcp` binary.
macOS app artifact: set `ENABLE_MACOS_RELEASE=true`, or **Actions → Release → Run workflow** with **build_macos**.

Notarized Developer ID builds and Sparkle appcast are **not** automated yet.

## Smoke-test the Mac runner

```bash
gh workflow run macos.yml --repo veloxdevworks/agent-canvas
gh run watch --repo veloxdevworks/agent-canvas
```

If the job sits on **Waiting for a runner**: labels don’t match, runner is offline, or an org runner group doesn’t include this repo.
