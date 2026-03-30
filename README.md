<p align="center">
  <img src="Sources/Baguette/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Baguette icon" width="72" />
</p>

# Baguette

macOS app (SwiftUI + RealityKit) to generate a `.usdz` 3D model from images (Apple Object Capture).

## Requirements

- macOS 26+
- Machine compatible `PhotogrammetrySession`

## Run

```bash
swift run
```

## Tests

```bash
swift test
```

## Build App (Xcode)

```bash
xcodebuild -project Baguette.xcodeproj -scheme Baguette -configuration Debug -destination 'platform=macOS' build
```

## License

GNU GPL v3.0. See [LICENSE](LICENSE).
