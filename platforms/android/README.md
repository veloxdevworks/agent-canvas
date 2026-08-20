# Agent Canvas for Android

Fixtures-only Glance renderer for schema v1. **No cloud, no OAuth, no sign-in, no MCP.**

Compiled identities are **`one` through `twelve`**. Size is chosen when you place a widget (Glance small / medium / large), not baked into the id.

## Open in Android Studio

1. Open the `platforms/android` directory (or **File → Open** that folder).
2. Let Gradle sync. SDK: **compileSdk 35**, **minSdk 26**.
3. Run the **app** configuration on a device or emulator (API 26+).

From the repo root:

```bash
just android-assemble
# or:
cd platforms/android && ./gradlew :app:assembleDebug
```

The debug APK is `platforms/android/app/build/outputs/apk/debug/app-debug.apk`.

If the Android SDK is missing, set `ANDROID_HOME` (or create `local.properties` with `sdk.dir=…`) and install **Android SDK Platform 35** plus Build-Tools 35.

## Host app

The host is the dogfood surface:

1. Pick a **size** chip (Small / Medium / Large). Preview uses approximate Glance tile sizes (170×170, 364×170, 364×382 dp).
2. Pick a **definition** (`one` … `twelve`).
3. Pick a bundled **fixture**. Tapping a fixture parses the JSON and updates the Compose preview.
4. **Pin to {definition}** writes that fixture to local DataStore and refreshes that definition’s widgets.
5. **Clear** unassigns the definition (empty canvas, not an error).

Invalid JSON fails in the host with an explicit parse error. The empty fixture is an empty canvas.

Bundled fixtures (copied from `schema/fixtures/`, not rewritten):

- `empty.json`
- `sample-metrics.json`
- `demo-sm-one.json`, `demo-md-one.json`, `demo-md-two.json`
- `demo-lg-one.json`, `demo-lg-two.json`, `demo-xl-one.json`
- `expressiveness.json`, `actions.json`, `cover.json`

## Add a widget

1. Long-press the home screen → **Widgets** → **Agent Canvas**.
2. Place **One** … **Twelve** (kinds `AgentCanvas.one` … `AgentCanvas.twelve`).
3. Resize to small / medium / large. The same document is packed to that size.
4. Open the host, choose a fixture, **Pin to** that definition. The widget updates.

Tapping a widget opens the host preview. List `action` / `onOpen` are no-ops in this slice except that tile tap.

## Glance limitations

- Charts: Compose preview draws bar / line / pie / gauge. Glance has no canvas path API, so widgets show a simple bar row or a `bar · N points` placeholder.
- Icons: Compose uses Material icons; Glance uses compact text glyphs.
- Badges / groups: Glance flattens to one line / stacked children. `group` is detail-only in the schema.
- Cover / image: `data:image/…;base64` decodes; `asset:{sha}` is unavailable here and falls back (cover alt + sections).
- Overflow is packed first, then clipped to the tile. A `+N more` caption matches the Apple shells when content does not fit.

## Layout

```
platforms/android/
├── app/src/main/assets/fixtures/   # schema fixtures shipped in the APK
├── app/src/main/java/dev/velox/agentcanvas/
│   ├── canvas/                     # models, parser, LayoutSpec, ContentClip
│   ├── ui/                         # host + Compose preview
│   ├── store/                      # DataStore assignments
│   └── widget/                     # 12 Glance receivers
└── README.md
```
