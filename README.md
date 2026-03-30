# <img src="Sources/Baguette/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Baguette icon" width="28" /> Baguette

macOS application (SwiftUI + RealityKit) that generates a 3D `.usdz` model from a batch of images using Apple Object Capture.

## Install (for users)

If you only want to use the app (without building from source), install it from the `.dmg`
attached to the latest GitHub Release.

1. Open the project Releases page on GitHub.
2. Download `Baguette-<version>-macos-arm64.dmg`.
3. Open the `.dmg`, then drag `Baguette.app` to `Applications`.
4. Launch `Baguette` from `Applications`.

Note: this release is currently not notarized, so macOS Gatekeeper may display a warning
on first launch.

## Features

- 3-step workflow split across tabs: `Import`, `Process`, `Scale`.
- Drag and drop image files into the app, or import from the file picker.
- Supported formats: `jpg`, `jpeg`, `png`, `heic`, `tiff`, `tif`.
- Inline thumbnail preview of dropped images.
- Quality selection before generation with 3 levels:
  - `Low` → Object Capture detail `.preview`
  - `Normal` → Object Capture detail `.medium`
  - `High` → Object Capture detail `.full`
- High-quality prewarm generation is started in the background after image import, and can be reused when launching generation.
- Asynchronous generation with progress updates.
- Generation cancellation during processing.
- Export (`Share`) of the latest generated/scaled `.usdz` file to a user-selected destination.
- Interactive scaling tab:
  - point-picking measurement directly on the 3D model surface (2 points),
  - automatic fill of the uncalibrated distance,
  - wireframe toggle on model click (outside measurement mode),
  - scaling from measured ratio (`real / uncalibrated`).
- User-facing error messages for unsupported devices and invalid input.
- Ephemeral in-app feedback banners for user actions (import, generate, scale, save, cancel).

## Architecture

- `ContentView`: root container with tab access control and export action.
- `ImportPhotosTabView`: image import/drop zone and thumbnail grid.
- `ProcessSettingsTabView`: quality selection, generation status, generate/stop actions.
- `ScaleTabView`: scaling workflow and measurement controls.
- `SurfaceMeasurementView`: SceneKit bridge for point picking and on-surface distance measurement.
- `PhotogrammetryViewModel`: orchestration of UI state and user actions.
- `PhotogrammetryServicing` / `PhotogrammetryService`: service layer isolating RealityKit.
- `TemporaryGenerationStore`: temporary workspace lifecycle for Object Capture input/output.
- `ScalingUseCase` / `USDZScaler`: validated USDZ scaling flow (`real / uncalibrated`) persisted back to disk.
- `ProcessingState`: high-level domain state (`idle`, `ready`, `processing`, `cancelled`, `completed`, `failed`).
- `SupportedImageFormat`: single source of truth for supported extensions.

This separation keeps the Object Capture workflow isolated from SwiftUI state updates and makes future evolution easier.

## Prerequisites

- macOS 26 (Tahoe).
- Machine compatible with `PhotogrammetrySession` (Apple Object Capture).

## Run

```bash
swift run
```

## Testing

```bash
swift test
```

Or use:

```bash
./Scripts/test.sh
```

## Build a `.app` (CLI + Xcode UI)

The SwiftPM package remains the simplest path for fast development (`swift run`).
To produce a real macOS `Baguette.app` bundle, use the Xcode project `Baguette.xcodeproj`.

### CLI build

```bash
xcodebuild -project Baguette.xcodeproj \
  -scheme Baguette \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

The `.app` is then available in the DerivedData directory, for example:

```text
~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/Baguette.app
```

### CLI build with controlled output path

```bash
xcodebuild -project Baguette.xcodeproj \
  -scheme Baguette \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/BaguetteLocal \
  build
```

Matching output path:

```text
~/Library/Developer/Xcode/DerivedData/BaguetteLocal/Build/Products/Debug/Baguette.app
```

### Launch the generated app

```bash
open ~/Library/Developer/Xcode/DerivedData/BaguetteLocal/Build/Products/Debug/Baguette.app
```

### Signing

The Xcode target is configured for local development signing (`CODE_SIGN_STYLE = Automatic`), suitable for local build/test.

## App icon

The Dock icon is provided by `Assets.xcassets/AppIcon.appiconset` (asset catalog), used by the Xcode target.
To regenerate PNG renders and the `.icns` fallback:

```bash
./Scripts/generate_app_icon.sh
```

## GitHub Release DMG

The repository includes a dedicated workflow that builds and publishes a macOS `.dmg`
artifact on GitHub Releases.

- Workflow: `.github/workflows/release.yml`
- Trigger on tags matching `v*` (for example `v1.2.3`)
- Manual trigger via `workflow_dispatch` (run it on a `v*` tag ref)
- Output asset name: `Baguette-<version>-macos-arm64.dmg`

Create and push a release tag:

```bash
git tag v1.2.3
git push origin v1.2.3
```

The workflow will:

1. Build `Baguette.app` in `Release` using Xcode.
2. Package the app into a compressed DMG.
3. Generate a SHA-256 checksum file.
4. Attach both files to the corresponding GitHub Release.

Manual packaging helper:

```bash
./Scripts/create_dmg.sh /path/to/Baguette.app 1.2.3
```

This first iteration does not include Developer ID signing or Apple notarization,
so Gatekeeper can display a warning on download/open.

## License

This project is licensed under the GNU General Public License v3.0.
See [LICENSE](LICENSE).
