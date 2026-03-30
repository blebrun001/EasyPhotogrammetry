# Baguette

macOS application (SwiftUI + RealityKit) that generates a 3D `.usdz` model from a batch of images using Apple Object Capture.

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

## Current limitations

- `.usdz` output is generated in a temporary directory;
- each new generation creates a new temporary input/output workspace;
- scaling currently writes a new file (`scaled_<original_name>.usdz`) instead of overwriting in place from the UI;
- generated temporary workspaces are cleaned at app shutdown.

## License

This project is licensed under the GNU General Public License v3.0.
See [LICENSE](LICENSE).
