# Floor Age

**How old does your body move?** An iOS fitness app built around one number, your *Floor Age*. It comes from four simple at-home tests: sit to rise from the floor, one-leg balance, a 30-second chair stand and a toe reach. A 3D coach demonstrates every move and talks you through daily sessions that target your weakest area.

## What's in the app

- **3D coach avatar** (RealityKit). It demonstrates each exercise. Drag to turn it, pinch to zoom, double-tap to reset.
- **Voice coaching** using the iPhone's built-in voices (Indian English by default). It works offline, ducks your music, and still speaks when the phone is on silent.
- **Floor Age check.** Four guided tests produce an estimated "equivalent age" for each area and overall, plus a shareable card.
- **Daily plan.** About 10 minutes: a warm-up plus exercises for your weakest areas. Moves are skipped or adapted for knee, hip or back problems.
- **Consistency tracking.** Shows how many of the last 7 days you trained. Missing a day never resets your progress.
- **Coach chat.** Ask questions like "I only have 10 minutes today". This goes through a small server that holds the Claude API key.
- **Privacy.** Everything is stored on the phone. Only chat messages plus age, Floor Age, weakest area and limitations go to the coach server. Your name is never sent.

## Repository layout

| Path | What it is |
|---|---|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated from it and not committed. |
| `FloorAge/` | SwiftUI app source (iOS 18+) |
| `FloorAge/Resources/exercises.json` | Avatar skeleton, poses and the exercise library (keyframes, cues, rep timing) |
| `tools/pose_preview.py` | Renders stick-figure previews of every exercise from `exercises.json` (no Mac needed) |
| `server/` | Coach chat server (Node + TypeScript + Anthropic SDK) |
| `.github/workflows/ios-build.yml` | Builds on GitHub's macOS machines on every push, plus simulator screenshots |
| `.github/workflows/testflight.yml` | Manually triggered signed build uploaded to TestFlight |

## Building without a Mac

Every push to `main` builds the app on GitHub Actions (`macos-26`) and uploads simulator screenshots of the coach as an artifact (**Actions → iOS build → Artifacts**).

### Put a build on your iPhone (TestFlight)

One-time setup:

1. **Register the bundle ID.** At developer.apple.com go to **Certificates, IDs & Profiles → Identifiers → +** and choose **App IDs** with the explicit ID `com.jeyaraj.floorage`. To use a different ID, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` and the ID in `ios-build.yml`.
2. **Create the app.** In App Store Connect go to **Apps → + → New App**, pick that bundle ID and name it (the name must be unique on the App Store).
3. **Create an API key.** In App Store Connect go to **Users and Access → Integrations → App Store Connect API → +** and give it the **Admin** role, which cloud signing needs. Download the `.p8` file (you can only download it once) and note the Key ID and Issuer ID.
4. **Add the secrets.** In GitHub go to **Settings → Secrets and variables → Actions** and add:
   - `APPLE_TEAM_ID` from developer.apple.com → Membership
   - `ASC_KEY_ID` and `ASC_ISSUER_ID`
   - `ASC_KEY_P8`: paste the whole contents of the `.p8` file
   - Optionally the **variable** `COACH_SERVER_URL`, once the coach server is deployed

Then open **Actions → TestFlight → Run workflow**. When App Store Connect finishes processing (usually 5–15 min), the build appears in the TestFlight app on your iPhone.

### On a Mac (optional)

```bash
brew install xcodegen
xcodegen generate
open FloorAge.xcodeproj
```

Pick your team under **Signing & Capabilities** and run on the simulator or a plugged-in iPhone.

## Editing exercises

Poses live in `FloorAge/Resources/exercises.json`. Joint angles are in degrees, applied Y (twist), then Z (sideways), then X (forward/back). Each keyframe says what touches the floor (`feet`, `left`, `right`, `seat`, `lowest`), and the solver keeps that contact planted. Preview changes on any computer:

```bash
python tools/pose_preview.py            # every exercise -> tools/out/<id>.png
python tools/pose_preview.py squat      # just one
```

## Coach chat server

```bash
cd server
npm install
cp .env.example .env    # add ANTHROPIC_API_KEY and an APP_TOKEN of your choice
npm run dev
```

The server is `POST /coach` with `{ messages, context }` and returns `{ reply }`. `GET /health` is a health check. Deploy it to any Node host (Render, Railway, Fly.io, a VPS), then enter the URL and the `APP_TOKEN` in the app under **Settings → Coach chat server**, or bake the URL into TestFlight builds with the `COACH_SERVER_URL` variable. It uses `claude-opus-5` with low effort for quick spoken replies. Override the model with `COACH_MODEL`. Server-side fallbacks are enabled, so if the model declines a request, the API retries it on a suitable fallback model.

## Floor Age scoring

Each test result maps to an "equivalent age" by interpolating along approximate age norms from published reference data. The sources are in `FloorAge/Models/FloorAge.swift`. The overall Floor Age is a weighted average. It is a **fitness estimate, not a medical diagnosis**, and the norms should be refined with real user data.
