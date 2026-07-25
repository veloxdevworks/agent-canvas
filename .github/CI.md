# CI notes (cost-aware)

macOS GitHub-hosted runners are billed at a much higher per-minute rate than Linux.
Until a **self-hosted Mac runner** is available, keep automatic macOS jobs off.

## Workflows

| Workflow | When | Runner | Purpose |
|----------|------|--------|---------|
| **CI** (`ci.yml`) | PR / push to `main` (skips pure doc changes) | `ubuntu-latest` | `fmt` · `clippy` · `test` · release-build MCP |
| **macOS** (`macos.yml`) | **Manual** by default | `macos-14` or `MACOS_RUNNER` | XcodeGen + unsigned `xcodebuild` |
| **Release** (`release.yml`) | Tag `v*.*.*` or manual | Linux always; macOS optional | GitHub Release + artifacts |

## Kill-switches & opt-ins (repo **Variables**)

Settings → Secrets and variables → Actions → **Variables**:

| Variable | Effect |
|----------|--------|
| `CI_DISABLED=true` | Skip automatic Linux CI jobs |
| `ENABLE_MACOS_CI=true` | Run macOS workflow on PR/push (paths under `platforms/macos/`) |
| `ENABLE_MACOS_RELEASE=true` | Build unsigned `.app` zip on version tags |
| `MACOS_RUNNER` | Override runner label (e.g. `self-hosted-macos`) |

You can also disable a workflow entirely under **Actions → workflow → … → Disable workflow**.

## Releasing

```bash
# 1. Update CHANGELOG.md [Unreleased] → [x.y.z]
# 2. Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in platforms/macos/project.yml
git tag v0.2.0
git push origin v0.2.0
```

Creates a GitHub Release with auto notes + Linux `agent-canvas-mcp` binary.
macOS app artifact: either set `ENABLE_MACOS_RELEASE`, or **Actions → Release → Run workflow** with **build_macos**.

Notarized Developer ID builds and Sparkle appcast are **not** automated yet (local/`just` + secrets later).

## Self-hosted Mac (later)

1. Register a runner with label e.g. `self-hosted-macos`
2. Set variable `MACOS_RUNNER=self-hosted-macos`
3. Optionally set `ENABLE_MACOS_CI=true` for PR gates on Swift changes
