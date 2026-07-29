# CI notes (cost-aware)

Validation jobs stay on GitHub-hosted `ubuntu-latest` (fmt, clippy, tests, MCP build).
We do **not** ship a standalone Linux MCP binary — without a host UI it is not useful.

**macOS / self-hosted Mac:** do **not** attach the org runner to this **public** repo for
routine CI (untrusted PR risk). Use the private companion:

→ **[`veloxdevworks/agent-canvas-release`](https://github.com/veloxdevworks/agent-canvas-release)**  
  (checkout a pin of this repo → Xcode build on the org MacBookPro)

Optional manual macOS workflow here remains `workflow_dispatch` only; prefer the private repo.

## Workflows

| Workflow | When | Runner | Purpose |
|----------|------|--------|---------|
| **CI** (`ci.yml`) | PR / push to `main` (skips pure doc changes) | `ubuntu-latest` | `fmt` · `clippy` · `test` · release-build MCP |
| **macOS** (`macos.yml`) | **Manual** by default; PR/push if `ENABLE_MACOS_CI` | `MACOS_RUNS_ON` or `macos-14` | XcodeGen + unsigned `xcodebuild` |
| **Release** (`release.yml`) | Tag `v*.*.*` or manual | `ubuntu-latest` (+ optional macOS) | GitHub Release notes; optional unsigned `.app` zip |

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

GitHub matches **all** labels in the array. This org’s MacBookPro runner (Intel) has:

```text
self-hosted
macOS
X64
```

(Apple Silicon machines use `ARM64` instead of `X64`.)

```bash
# Intel (current veloxdevworks MacBookPro)
gh variable set MACOS_RUNS_ON --repo veloxdevworks/agent-canvas \
  --body '["self-hosted","macOS","X64"]'

# Apple Silicon
# gh variable set MACOS_RUNS_ON --repo veloxdevworks/agent-canvas \
#   --body '["self-hosted","macOS","ARM64"]'
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

Cut only from a clean tree after preflight. Do **not** use a real version tag
only to discover notarize/Sparkle or menu-bar UX bugs — dry-run packaging
first when those scripts change.

### Ship checklist (before `git tag`)

```bash
# 1. Move CHANGELOG.md [Unreleased] → [x.y.z] (leave [Unreleased] empty)
# 2. Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in platforms/macos/project.yml
# 3. Commit everything that belongs in the cut (no half-landed features)
just release-preflight
```

`just release-preflight` fails the cut early if:

- the working tree is dirty (override: `ALLOW_DIRTY=1`)
- `CHANGELOG` lacks `## [x.y.z]` for the version in `project.yml`
- menu-bar UX is incomplete (`MenuBarExtraView` is the primary surface — items
  only in `AgentCanvasCommands` do **not** count as shipped)
- Settings General is missing Updates / Privacy
- Sparkle `Info.plist` keys are missing
- a **Release** `.app` build fails (catches `#if DEBUG` / Release-only breakage)
- Swift unit tests fail

Optional: `SKIP_BUILD=1 just release-preflight` for string/git checks only.

After automated checks pass, walk the printed human checklist on a Release
install (`CONFIGURATION=Release just macos-install && just macos-run`):

- [ ] Menu bar: Settings, Connect MCP, How to Use, Send Feedback, Report Issue,
      Check for Updates…, Quit
- [ ] Settings → General: Updates + Privacy match the product story
- [ ] If packaging / Sparkle scripts changed: private workflow with
      `publish_public=false` (or local notarize) before a public tag

Then tag and push:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Creates a GitHub Release with auto notes (and source archives). Installable
binaries are the notarized macOS DMGs from the private companion — not a
standalone MCP for Linux/Windows.

### Notarized macOS DMGs (private companion)

Signing / notarization / DMG packaging run only in the private repo (secrets + org Mac):

→ **[`veloxdevworks/agent-canvas-release`](https://github.com/veloxdevworks/agent-canvas-release)**

Shared scripts (this tree, at the release tag):

- [`scripts/macos/build-release-app.sh`](../scripts/macos/build-release-app.sh) — arch-specific Release `.app` + embedded MCP  
- [`scripts/macos/package-notarized-dmg.sh`](../scripts/macos/package-notarized-dmg.sh) — Developer ID sign → notarize → DMG (also resigns Sparkle frameworks/XPCs)  
- [`scripts/macos/make-universal-app.sh`](../scripts/macos/make-universal-app.sh) — lipo x86_64 + arm64 → universal `.app`  
- [`scripts/macos/publish-sparkle-appcast.sh`](../scripts/macos/publish-sparkle-appcast.sh) — universal zip + EdDSA-signed `appcast.xml`

The private workflow prefers a dedicated runner keychain
(`~/Library/Keychains/agent-canvas.keychain-db`) unlocked via
`~/.agent-canvas-keychain-password`.

```bash
# After the public tag exists (and Release workflow has created the GitHub Release):
gh workflow run release.yml --repo veloxdevworks/agent-canvas-release \
  -f ref=v0.2.9 \
  -f release_tag=public-v0.2.9 \
  -f publish_public=true
```

Attaches to the **public** Release:

- `AgentCanvas-v0.2.9-x86_64.dmg` / `…-arm64.dmg` (first-time install)
- `AgentCanvas-v0.2.9.zip` (Sparkle enclosure, universal)
- `appcast.xml` (also reachable via `…/releases/latest/download/appcast.xml`)
- `SHA256SUMS.txt`

(Intel self-hosted runner builds `x86_64` natively and cross-compiles `arm64`.)

### Sparkle (in-app updates)

| Piece | Value |
|-------|--------|
| Feed | `https://github.com/veloxdevworks/agent-canvas/releases/latest/download/appcast.xml` |
| Public key | `SUPublicEDKey` in `platforms/macos/AgentCanvas/Info.plist` |
| Private key | Actions secret `SPARKLE_PRIVATE_ED_KEY` on **agent-canvas-release** |
| Host UX | **Check for Updates…** + automatic checks (`SUEnableAutomaticChecks`) |

Generate / rotate keys (once per organization):

```bash
# From a Sparkle release tarball:
./bin/generate_keys                 # prints SUPublicEDKey; stores private in login keychain
./bin/generate_keys -x sparkle_private_ed_key.txt
gh secret set SPARKLE_PRIVATE_ED_KEY --repo veloxdevworks/agent-canvas-release \
  < sparkle_private_ed_key.txt
# Commit the new SUPublicEDKey in Info.plist when rotating.
```

**Tester note:** `v0.2.7` is the first Sparkle-capable build; `v0.2.8` proves the update path. Install 0.2.7 from the notarized DMG under `/Applications`, then **Check for Updates…** (or wait for the automatic check) to receive 0.2.8+.

Local dry-run (Developer ID + `notarytool` profile on your Mac):

```bash
CONFIGURATION=Release just macos-install
IDENTITY="Developer ID Application: …" NOTARY_PROFILE=agent-canvas-notary \
  just macos-notarize-dmg
```

Optional unsigned macOS zip from **this** public repo: set `ENABLE_MACOS_RELEASE=true`, or **Actions → Release → Run workflow** with **build_macos**. Prefer the private notarized DMGs for installs.

## Smoke-test the Mac runner

```bash
gh workflow run macos.yml --repo veloxdevworks/agent-canvas
gh run watch --repo veloxdevworks/agent-canvas
```

If the job sits on **Waiting for a runner**: labels don’t match, runner is offline, or an org runner group doesn’t include this repo.
