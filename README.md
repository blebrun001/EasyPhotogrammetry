<p align="center">
  <img src="Sources/Baguette/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Baguette icon" width="72" />
</p>

# Baguette

Application macOS (SwiftUI + RealityKit) pour générer un modèle 3D `.usdz` à partir d'images (Apple Object Capture).

## Prérequis

- macOS 26+
- Machine compatible `PhotogrammetrySession`

## Lancer

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

## Licence

GNU GPL v3.0. Voir [LICENSE](LICENSE).
