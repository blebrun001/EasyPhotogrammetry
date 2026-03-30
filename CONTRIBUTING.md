# Contributing Guide

## Commenting Standard

This project uses SwiftDoc (`///`) for API-level documentation and regular comments (`//`) for intent-level context.

### Language

- Write all comments and docstrings in English.

### What to document with `///`

- Non-trivial `struct`, `class`, `enum`, `protocol`, and nested types.
- Public and internal functions that carry business logic, side effects, validation, or concurrency behavior.
- Computed properties whose purpose is not immediately obvious.

### Function docstring format

Use this shape whenever applicable:

- One-line summary
- `- Parameters:`
- `- Returns:`
- `- Throws:`

Example:

```swift
/// Validates and normalizes raw user input before scaling.
/// - Parameters:
///   - file: Selected USDZ file.
///   - uncalibrated: Uncalibrated measurement text.
///   - real: Real-world measurement text.
///   - overwrite: Whether to overwrite the source file.
/// - Returns: A validated scaling request.
/// - Throws: `ScalingError.invalidInput` when values are missing or invalid.
func makeRequest(file: URL?, uncalibrated: String, real: String, overwrite: Bool) throws -> ScalingRequest
```

### What to document with `//`

Use inline comments only for "why" context:

- Business rules.
- Edge-case handling.
- Workarounds and platform constraints.
- Non-obvious ordering/concurrency decisions.

### Avoid noisy comments

Do not add comments that simply restate the code.

Bad:

```swift
// Set state to processing
state = .processing(progress: progress)
```

Good:

```swift
// Keep progress monotonic to avoid UI regressions when callbacks arrive out of order.
state = .processing(progress: max(current, incoming))
```

## PR Checklist (Documentation)

- Added or updated `///` docstrings when introducing or changing non-trivial logic.
- Documented side effects (file writes/deletes, cleanup, cancellation, task lifecycle).
- Documented validation and error behavior (`Throws` and failure conditions).
- Kept comments in English and aligned with project terminology (`generation`, `scaling`, `measurement`, `workspace`).
- Removed outdated or tautological comments.
