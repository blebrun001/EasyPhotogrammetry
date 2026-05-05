<p align="center">
  <img src="Sources/EasyPhotogrammetry/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="EasyPhotogrammetry icon" width="72" />
</p>

# EasyPhotogrammetry

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
xcodebuild -project EasyPhotogrammetry.xcodeproj -scheme EasyPhotogrammetry -configuration Debug -destination 'platform=macOS' build
```

## License

GNU GPL v3.0. See [LICENSE](LICENSE).
