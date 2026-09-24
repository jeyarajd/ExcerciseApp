# Floor Age

**How old does your body move?** An iOS fitness app built around one number, your *Floor Age*. It comes from four simple at-home tests: sit to rise from the floor, one-leg balance, a 30-second chair stand and a toe reach. A 3D coach demonstrates every move and talks you through daily sessions that target your weakest area. Everything runs on the phone: no account, no server and no running costs.

## What's in the app

- **3D coach avatar** (RealityKit). A realistic woman or man, matching the gender in your profile, demonstrates each exercise. Drag to turn it, pinch to zoom, double-tap to reset. Settings can switch to a friendly cartoon coach instead.
- **Demo videos.** A "Watch a real demo" clip for each exercise, bundled in the app and played offline.
- **Voice coaching** using the iPhone's built-in voices (Indian English by default). It works offline, ducks your music, and still speaks when the phone is on silent.
- **Floor Age check.** Four guided tests produce an estimated "equivalent age" for each area and overall, plus a shareable card.
- **Daily plan.** About 10 minutes: a warm-up plus exercises for your weakest areas, finishing with pelvic floor (Kegel) squeezes. Moves are skipped or adapted for knee, hip or back problems.
- **Pelvic floor.** Guided Kegel squeezes with "Squeeze and lift… And relax" timing, at the end of each plan (can be switched off) or as a 2-minute session from Today.
- **Consistency tracking.** Shows how many of the last 7 days you trained. Missing a day never resets your progress.
- **Track tab:**
  - **Steps:** today's steps against a goal you set, distance, and a 7-day chart, from the iPhone's own motion sensors (CoreMotion, Motion & Fitness permission). No account or HealthKit needed.
  - **Calories:** log meals from about 75 common Indian foods with typical portions, or add your own. **Snap your plate** takes a photo and suggests what's on it using Apple's on-device image classifier (it knows dishes like biryani, curry, naan, samosa, rice and raita, plus fruit and drinks). You tick the right items and set the servings, because no photo can show portion size. The photo never leaves the phone. The daily target comes from the Mifflin-St Jeor formula for your age, gender, height and weight.
  - **BMI:** height (cm or ft/in) and weight, a colour-coded result with encouragement, your healthy weight range, and a weight chart. It uses the lower BMI cut-offs recommended for South Asians (healthy 18.5–22.9).
- **Daily reminder.** Optional, at a time you pick. It's skipped on days you've already trained.
- **Editable profile.** Change your age or limitations in Settings. Your plan and safety filtering update right away.
- **Privacy.** Everything is stored on the phone and nothing is sent anywhere.
- **Look.** A warm, slowly drifting gradient behind every screen, glass cards, and the 3D coach standing right on the background.

## Repository layout

| Path | What it is |
|---|---|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated from it and not committed. |
| `FloorAge/` | SwiftUI app source (iOS 18+) |
| `FloorAge/Resources/exercises.json` | Avatar skeleton, poses and the exercise library (keyframes, cues, rep timing) |
| `FloorAge/Resources/Videos/` | Demo clips, `demo_<exercise id>.mp4` (see [Demo videos](#demo-videos)) |
| `FloorAgeTests/` | Unit tests: scoring, plan safety filtering, persistence, exercise data, pose solver, reminders |
| `tools/pose_preview.py` | Renders stick-figure previews of every exercise from `exercises.json` (no Mac needed) |
| `tools/build_coach.py` | Builds the realistic coach models `FloorAge/Resources/coach_*.usdz` in Blender (see [Realistic coach](#realistic-coach)) |
| `.github/workflows/ios-build.yml` | Builds on GitHub's macOS machines on every push, plus simulator screenshots |
| `.github/workflows/testflight.yml` | Manually triggered signed build uploaded to TestFlight |

## Building without a Mac

Every push to `main` builds the app on GitHub Actions (`macos-26`), runs the unit tests, and uploads simulator screenshots of the coach as an artifact (**Actions → iOS build → Artifacts**).

### Put a build on your iPhone (TestFlight)

One-time setup:

1. **Register the bundle ID.** At developer.apple.com go to **Certificates, IDs & Profiles → Identifiers → +** and choose **App IDs** with the explicit ID `com.jeyaraj.floorage`. To use a different ID, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` and the ID in `ios-build.yml`.
2. **Create the app.** In App Store Connect go to **Apps → + → New App**, pick that bundle ID and name it (the name must be unique on the App Store).
3. **Create an API key.** In App Store Connect go to **Users and Access → Integrations → App Store Connect API → +** and give it the **Admin** role, which cloud signing needs. Download the `.p8` file (you can only download it once) and note the Key ID and Issuer ID.
4. **Add the secrets.** In GitHub go to **Settings → Secrets and variables → Actions** and add:
   - `APPLE_TEAM_ID` from developer.apple.com → Membership
   - `ASC_KEY_ID` and `ASC_ISSUER_ID`
   - `ASC_KEY_P8`: paste the whole contents of the `.p8` file

Then open **Actions → TestFlight → Run workflow**. When App Store Connect finishes processing (usually 5–15 min), the build appears in the TestFlight app on your iPhone.

### On a Mac (optional)

```bash
brew install xcodegen
xcodegen generate
open FloorAge.xcodeproj
```

Pick your team under **Signing & Capabilities** and run on the simulator or a plugged-in iPhone. Run the unit tests with **Product → Test** (⌘U) or:

```bash
xcodebuild test -project FloorAge.xcodeproj -scheme FloorAge -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Editing exercises

Poses live in `FloorAge/Resources/exercises.json`. Joint angles are in degrees, applied Y (twist), then Z (sideways), then X (forward/back). Each keyframe says what touches the floor (`feet`, `left`, `right`, `seat`, `lowest`), and the solver keeps that contact planted. Preview changes on any computer:

```bash
python tools/pose_preview.py            # every exercise -> tools/out/<id>.png
python tools/pose_preview.py squat      # just one
```

## Demo videos

Each exercise can have a short real-person demo clip next to the 3D coach. Clips are bundled in the app, so they play offline and cost nothing to host.

- Put them in `FloorAge/Resources/Videos/` named `demo_<exercise id>.mp4`, for example `demo_squat.mp4`. The IDs are in `exercises.json`.
- Run `xcodegen generate` after adding or removing a clip.
- An exercise without a clip shows no video button, so you can add clips one at a time. A unit test flags clips that don't match an exercise ID.
- The current clips are stick-figure **placeholders** generated from the poses. Replace them before release.
- Tips for filming: landscape or portrait both work. Keep each clip to 5–15 seconds of one clean, looping rep (it loops automatically), under about 5 MB (1080p H.264). Show the easier version if there is one, and film near a wall or chair where the safety note says to use one.

## Realistic coach

The realistic coaches (`FloorAge/Resources/coach_female.usdz`, `coach_male.usdz`) are made with [MakeHuman](http://www.makehumancommunity.org) via its Blender add-on MPFB. Everything exported comes from CC0 asset packs, so it's free to ship. The app poses their skeleton from the same `exercises.json` keyframes as the cartoon coach (`FloorAge/Avatar/RealisticCoach.swift`).

To change a coach's look (body shape, skin, hair, clothes), edit `COACHES` in `tools/build_coach.py` and rebuild on a Mac:

1. Install Blender 4.2+ and the MPFB extension (extensions.blender.org/add-ons/mpfb).
2. Load the CC0 packs `makehuman_system_assets`, `skins01`, `skins02`, `hair01`, `shirts01`, `pants01` and `shoes01` from the [asset packs page](https://static.makehumancommunity.org/assets/assetpacks/index.html) into MPFB.
3. Run `blender -b --python tools/build_coach.py -- FloorAge/Resources`, then `xcodegen generate`.

## Floor Age scoring

Each test result maps to an "equivalent age" by interpolating along approximate age norms from published reference data. The sources are in `FloorAge/Models/FloorAge.swift`. The overall Floor Age is a weighted average. It is a **fitness estimate, not a medical diagnosis**, and the norms should be refined with real user data.
