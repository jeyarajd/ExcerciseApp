# Floor Age

Native iOS app (SwiftUI, RealityKit, iOS 18+) plus a small Node/TypeScript coach server. See README.md for features and setup.

## Build

- The Xcode project is generated: `xcodegen generate` (from `project.yml`). Never commit `*.xcodeproj` or `FloorAge/Info.plist`.
- Development usually happens on Windows without a Mac. Compile checks run on GitHub Actions (`.github/workflows/ios-build.yml`, runner `macos-26`). Read failures with `gh run view --log-failed`, and download simulator screenshots with `gh run download`.
- On a Mac: `xcodebuild build -project FloorAge.xcodeproj -scheme FloorAge -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Swift language mode is 5 (`SWIFT_VERSION: "5.0"`). Models are `ObservableObject` classes, not `@Observable`.
- Server: `cd server && npm run build` (tsc). It uses `@anthropic-ai/sdk` with `claude-opus-5`, low effort, and `fallbacks: "default"`.

## Avatar

- `FloorAge/Resources/exercises.json` is the single source of truth for the skeleton, poses and exercises. `tools/pose_preview.py` and `FloorAge/Avatar/PoseAnimator.swift` implement the same FK, ground solver and blending. Change both together.
- Euler order: `q = qx * qz * qy` (twist Y first, then Z, then X). For a limb pointing down, negative X swings it forward. For the spine, positive X bends forward. Left is +X.
- After editing poses, run `python tools/pose_preview.py <id>` and look at `tools/out/<id>.png` before committing.
- Demo launch arguments for screenshots: `-demoExercise <id> -demoTime <seconds>`.

## Conventions

- Keep all personal data on the device (`AppModel` JSON file). Only chat text and the small `CoachClient.Context` go to the server, never the name.
- Floor Age is a fitness estimate, never medical advice. Keep safety copy and limitation filtering (`PlanBuilder.unsafe`) intact when adding exercises.
