# Baguette

Application macOS (SwiftUI + RealityKit) pour générer un modèle 3D `.usdz` à partir d'un lot d'images via Apple Object Capture.

## Objectif

Fournir un point de départ simple, lisible et maintenable pour un workflow de photogrammétrie local:

- import par glisser-déposer;
- validation explicite des formats supportés;
- génération asynchrone avec suivi de progression;
- accès direct au fichier de sortie.

## Architecture

- `ContentView`: interface utilisateur (drop zone, actions, état affiché).
- `PhotogrammetryViewModel`: orchestration de l'état UI et des actions utilisateur.
- `PhotogrammetryServicing` / `PhotogrammetryService`: couche de service isolant RealityKit.
- `ProcessingState`: état métier de haut niveau (`idle`, `ready`, `processing`, `completed`, `failed`).
- `SupportedImageFormat`: source unique de vérité pour les extensions supportées.

Cette séparation évite le couplage UI / API système et facilite les évolutions futures (tests, options de détail, persistance).

## Prérequis

- macOS 13+.
- Machine compatible avec `PhotogrammetrySession` (Apple Object Capture).

## Exécution

```bash
swift run
```

## Choix de qualité pour éviter le "vibe coding"

- comportements critiques explicités et centralisés (validation formats, progression bornée);
- pas de logique dupliquée entre UI et service;
- erreurs métier dédiées et messages lisibles;
- conventions simples et stables pour limiter les régressions.

## Limites actuelles

- sortie `.usdz` générée dans un répertoire temporaire;
- niveau de détail fixé à `.full`;
- pas encore de suite de tests automatisés.
