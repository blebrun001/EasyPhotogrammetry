# Baguette

macOS application (SwiftUI + RealityKit) that generates a 3D `.usdz` model from a batch of images using Apple Object Capture.

## Features

- Drag and drop image files into the app.
- Supported formats: `jpg`, `jpeg`, `png`, `heic`, `tiff`, `tif`.
- Inline thumbnail preview of dropped images.
- Quality selection before generation: `Preview`, `Reduced`, `Medium`, `Full`, `Raw`.
- Asynchronous generation with progress updates.
- One-click opening of the generated `.usdz` file.
- USDZ scaling tab with calibrated ratio input and overwrite/new-file mode.
- User-facing error messages for unsupported devices and invalid input.

## Architecture

- `ContentView`: user interface (drop zone, actions, displayed state).
- `PhotogrammetryViewModel`: orchestration of UI state and user actions.
- `PhotogrammetryServicing` / `PhotogrammetryService`: service layer isolating RealityKit.
- `ScalingUseCase` / `USDZScaler`: validated USDZ scaling flow (`real / uncalibrated`) persisted back to disk.
- `ProcessingState`: high-level domain state (`idle`, `ready`, `processing`, `completed`, `failed`).
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
- no automated test suite yet.
