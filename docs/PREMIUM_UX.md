# Premium UX brief (Floor Age)

A to-do list for giving Floor Age a premium feel. It follows the rules in `CLAUDE.md`: offline only, `String(localized:)` for every string, optional new fields in `Stored`/`Profile`, and the free/Plus split stays as it is. Work top to bottom. Each item says where to make the change and how to check it's done.

## 0. New realistic coaches (done on this branch)

- `FloorAge/Resources/coach_female.usdz` and `coach_male.usdz` have been rebuilt with `tools/build_coach.py` (v2 looks).
- South Asian coaches in their early 30s with athletic builds, which suits the Indian English default voice and family use.
- Matching brand kit: a teal training tee (`Feature.calories` teal) over black running tights with white piping, and white trainers with orange accents. The man also wears charcoal training shorts. The woman's crop top was swapped for a full tee, which suits family use.
- Skin is less glossy (roughness 0.68, lower specular), fabric is matte (0.85), and the hair is natural black.
- The skeleton is still the MPFB `game_engine` rig, and the bone names haven't changed, so `RealisticCoach.boneFor` and `aimAt` work without edits.
- Preview renders are in `docs/coach_previews/`.
- To check: run `-demoScreen today -coachLook female` and then `-coachLook male`, plus `-demoExercise squat -demoTime 1.2`. Make sure the tee doesn't clip through the tights at the waist during squats and sit-to-rise. If it does, raise `waist += 0.03` in `trim_above_waist`.
- The build now also runs on Blender 4.2 (`export_textures` fallback). `PREVIEW=<dir> blender -b --python tools/build_coach.py -- <out>` renders studio previews.

## 1. Coach presentation (the hero of the app) (done)

1. **Face and hands lighting.** In `AvatarController.makeView`, bring `key.light.intensity` down to about 1800 and turn the rim light up to about 1200, so the new darker skin tones keep their shape against the peach background. Set `intensityExponent` to between 0.6 and 0.8 for dark mode only.
2. **Idle life.** Between reps, add a slow weight shift (±1.5° pelvis roll over 4 s) on top of the existing breathing and blink. Add it in `PoseAnimator` so the stylized rig gets it too.
3. **Entrance.** When a session opens, fade the coach in and scale it from 0.96 to 1.0 (0.4 s spring) instead of popping it in. The contact shadow fades in with it.
4. **Camera choreography.** Set a preferred yaw for each exercise in `exercises.json` (for example, a side view for toe reach and hip hinge), and animate the camera there over 0.6 s when the exercise changes. Always respect Reduce Motion.
5. **Look-at.** During the intro and rest phases, turn the coach's head towards the camera (up to 20°), so it feels as if it's talking to you.

## 2. Motion and haptics (done)

- Use `.sensoryFeedback` (iOS 17 and later):
  - `.increase` on every counted rep (`SessionEngine.onRep`);
  - `.success` when an exercise or session is finished;
  - `.warning` when camera scoring loses the body;
  - `.selection` on the speed and coach pickers.
- Rep counter: use `.contentTransition(.numericText())` plus a short scale pulse. The countdown already does this.
- Symbols: use `.symbolEffect(.bounce)` on the finished checkmark, and `.symbolEffect(.pulse)` on the camera icon while it's tracking.
- Screen changes: use `matchedGeometryEffect` or `navigationTransition(.zoom)` from the Today hero card into the session, so the coach seems to step forward.
- Keep every animation under 0.5 s, and skip decorative motion when `accessibilityReduceMotion` is on.

## 3. Session screen polish (`Features/Session/SessionView.swift`) (done)

- A **progress ring** round the rep counter that fills per set. Use the `Feature` colours of the area being trained.
- **Next up** card during rest: exercise name, a thumbnail pose (render the rig's first keyframe into an image once and cache it). Done with `PoseThumbnail`: the keyframe furthest from standing, since most first keyframes are just standing, drawn side-on in the camera mannequin style, and a "Skip rest" button.
- **Cue capsule:** a material background (`.ultraThinMaterial`) with a thin brand-gradient stroke looks more premium than a solid accent capsule. Keep the contrast at 4.5:1 or more.
- **Session complete:** a full-screen summary with minutes, reps, the area improved, and a streak flame. Offer a "Share" button that reuses `ShareCard`.

## 4. Today and onboarding (done)

- The Today hero shows a live, slowly idling coach (small `AvatarView`, no gestures) next to the Floor Age gauge, not a static card.
- Onboarding: choose a coach (woman or man, realistic or cartoon) with a live preview that turns slowly, and hear a short spoken hello with `VoiceCoach`.
- Skeleton loading states: use `.redacted(reason: .placeholder)` for cards while `AppModel` loads, so nothing jumps. `AppModel` loads synchronously, so this went where data really arrives late: the step gauges and week bars until CoreMotion or Health answers (`StepCounter.isLoading`).

## 5. Visual system (`App/Theme.swift`)

- Add a spacing and radius scale (4, 8, 12, 16, 24, 32 and radii 12, 20, 28) and use it everywhere instead of hard-coded numbers.
- Typography: `Font.display` (serif) for headings, and `Font.metric` (rounded) only for numbers. Make sure everything works with Dynamic Type up to `.accessibility3`.
- Hero cards: add a faint noise or grain overlay (2 to 3% opacity) and an inner highlight on the top edge for a richer gradient.
- Dark mode: check each `Feature` gradient for contrast on the night mesh.

## 6. Plus paywall (`Features/Plus/PlusView.swift`)

- A single clear hero: the coach in a victory pose, the price from StoreKit (`displayPrice`), and "one-time, no subscription" in bold.
- A feature list with a `FeatureBadge` for each `PlusFeature`, and a comparison row showing Free and Plus side by side.
- Restore Purchases stays visible (App Review requires it).
- After a purchase: confetti (a Canvas particle burst of 1.2 s, skipped with Reduce Motion) and `.sensoryFeedback(.success)`.

## 7. Performance feel

- Preload the coach USDZ on launch in a background task (`RealisticCoach.loadModel` cache), so the first session opens instantly.
- Keep 60 fps in the session: profile `RealisticCoach.apply` with Instruments. If needed, reuse arrays instead of allocating each frame.
- Keep app launch under 400 ms to the first frame. Defer HealthKit, pedometer and reminder refresh until after the first frame.

## 8. Checks before merging

- `xcodebuild test` passes on CI (`macos-26`).
- `python3 tools/check_translations.py` passes with every new string in English, Hindi and Spanish.
- Simulator screenshots from CI artifacts: Today, session squat, sit-to-rise, result, Plus (light and dark).
- VoiceOver pass on the session screen: rep count and cue are announced.
