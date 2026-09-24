# Floor Age: App Store listing guide

Everything App Store Connect asks for, in one place. The store text itself lives in `fastlane/metadata/` (fastlane `deliver` layout), so you can upload it with `fastlane deliver` or copy and paste each file.

Check the limits after any edit:

```bash
python3 tools/check_appstore_metadata.py
```

| Locale folder | App Store Connect language | Storefronts it mainly serves |
|---|---|---|
| `en-US` | English (U.S.) | US, India, and the fallback for every storefront without its own language |
| `hi` | Hindi | India (shown to people whose iPhone is set to Hindi) |
| `es-MX` | Spanish (Mexico) | Mexico and Latin America, and Spanish speakers in the US |
| `es-ES` | Spanish (Spain) | Spain |

Shared files: `copyright.txt` (2026 Jeyaraj David), `primary_category.txt` (Health & Fitness), `secondary_category.txt` (Lifestyle). Privacy and support URLs are in each locale folder.

---

## 1. Name, subtitle and keywords

| | en-US | hi | es-MX | es-ES |
|---|---|---|---|---|
| Name (30) | Floor Age: Sit-to-Rise Test | Floor Age: शरीर की उम्र | Floor Age: Levántate del piso | Floor Age: Levántate del suelo |
| Subtitle (30) | Body Age Check & 3D Home Coach | फ़र्श से उठने का टेस्ट, 3D कोच | Tu edad física y un coach 3D | Edad física y entrenador 3D |

**Why this name.** "Sit-to-rise test" is what people type after reading about the floor test in the news, and it's the one search where Floor Age is the most relevant app. It also tells a browser in two seconds what the app does. The brand stays first so the name reads as a product, not a generic utility.

**Why this subtitle.** The name covers the test; the subtitle adds the other two things people search for and the thing that makes the app different: "body age", "check", "home" and a "3D coach". Every word is indexed, so nothing repeats the name.

**Hindi.** "शरीर की उम्र" (body age) is the plain-language idea behind Floor Age, and the subtitle explains the floor test and the coach. Hindi App Store search is thin, so English loanwords (BMI, balance) are included in the keywords where people actually type them.

**Spanish.** "Levántate del piso/suelo" is a call to action that works as the hook. Mexico says *piso* for the floor, Spain says *suelo* (and *suelo pélvico*). Mexico uses "coach" comfortably; Spain prefers "entrenador".

**Keywords** (100 characters, comma-separated, no spaces, nothing repeated from the name or subtitle, singular forms only, since Apple matches plurals itself):

| Locale | Keywords |
|---|---|
| en-US | `balance,strength,mobility,workout,exercise,senior,parent,kegel,pelvic,step,calorie,bmi,sleep,5k` |
| hi | `संतुलन,ताकत,कसरत,व्यायाम,फ़िटनेस,बुज़ुर्ग,माता-पिता,कीगल,पेल्विक,कदम,कैलोरी,BMI,नींद,वज़न,balance` |
| es-MX | `equilibrio,fuerza,ejercicio,movilidad,mayores,papás,kegel,pélvico,pasos,calorías,imc,sueño,caminar` |
| es-ES | `equilibrio,fuerza,ejercicio,entreno,mayores,padres,kegel,pélvico,pasos,calorías,imc,sueño,caminar` |

Rationale: the four tests map to *balance, strength, mobility*; the audience to *senior/parent* (family profiles); Plus features to *kegel, pelvic, sleep, calorie, 5k*; free tracking to *step, bmi*. Words that would mislead (yoga, diet, weight loss, longevity) are deliberately left out, and so are competitor names, which App Review rejects. "Fitness" is dropped in English because the category already covers it.

**Promotional text** (170, editable any time without a new build) leads with the challenge question. Swap it for news later, for example "Now test your parents too with family profiles".

**Release notes.** App Store Connect doesn't show "What's New" for an app's first version, so `release_notes.txt` is ignored for 1.0 (fastlane may warn). Keep the files: edit them for 1.0.1.

---

## 2. App Privacy ("nutrition label")

Answer: **Data Not Collected.**

In App Store Connect › App Privacy › Get Started, answer **"No, we do not collect data from this app."**

Why that's accurate: Apple defines "collect" as transmitting data off the device in a way that you or a third party can access it for longer than it takes to handle the request in real time. Floor Age:

- has no server, account, analytics, crash-reporting, ad or tracking SDK (the project has no third-party packages);
- stores the profile, family profiles, test results, sessions, meals, weight and sleep in its own JSON file on the device;
- processes camera frames (camera scoring) and food photos on the device with Apple's Vision framework and discards them;
- reads sleep from HealthKit read-only, used only on the device;
- reads steps from CoreMotion on the device;
- schedules the evening reminder locally;
- handles the Plus purchase with StoreKit 2. Payment data goes to Apple, not to you. Apple's own processing doesn't count as your collection.

If you ever add analytics, crash reporting, iCloud sync to your own server, or a web form, this answer must change first.

Still needed despite "Data Not Collected":

- **Privacy policy URL** (required, and required for HealthKit apps): `https://jeyarajd.github.io/ExcerciseApp/privacy.html` (source: `AppStore/privacy.html`).
- **Privacy manifest.** Add `PrivacyInfo.xcprivacy` to the app target declaring *NSPrivacyTracking = false*, no collected data types, and the required-reason API for `UserDefaults` (`CA92.1`, the app's own settings), because the app uses `@AppStorage`/`UserDefaults`. Apple warns or rejects uploads without it. Done: `FloorAge/PrivacyInfo.xcprivacy`.

---

## 3. Age rating

Expected result: **4+.** Answer the questionnaire as follows. Apple shows the resulting rating before you save.

| Question | Answer | Note |
|---|---|---|
| Parental controls / Age assurance | No | |
| Unrestricted web access | No | The app opens no web views. |
| User-generated content | No | Profiles and logs stay private on the device. Sharing the Floor Age card uses the system share sheet, which isn't in-app UGC. |
| Messaging and chat | No | |
| Advertising | No | |
| Profanity, horror, alcohol/tobacco/drugs, violence, sexual content, nudity | None | The pelvic floor (Kegel) exercises are described as muscle exercises, with no sexual content. |
| Gambling, simulated gambling, contests, loot boxes | None / No | The share-card "challenge" has no prizes. |
| **Medical or Treatment Information** | **None** | See below. |
| Health or Wellness Topics (if the form asks this separately) | Yes | It's a fitness app. |

**Medical or Treatment Information: why "None".** This question is about content that gives medical or treatment information, such as symptoms, diagnoses, dosing or treatment advice. Floor Age gives general fitness guidance: exercise demonstrations, BMI and sleep ranges from public health bodies, and standard safety precautions ("talk to your doctor before starting", "use a wall for support", moves skipped for knee, hip or back problems). The safety copy is a precaution that points people *to* a doctor rather than medical information, and the app never diagnoses or treats. Answering "Infrequent/Mild" would be defensible if you want to be conservative, but it raises the rating above 4+ (to 9+/13+ depending on the current questionnaire), which would put the app off-limits under many families' Screen Time settings for no real benefit. If App Review disagrees, change the answer; it doesn't require a new build.

---

## 4. Category

- Primary: **Health & Fitness** (`HEALTH_AND_FITNESS`)
- Secondary: **Lifestyle** (`LIFESTYLE`)

---

## 5. In-app purchase metadata

Type **Non-Consumable**, product ID `com.jeyaraj.floorage.plus`, reference name "Floor Age Plus". Suggested price tier: USD 4.99 / INR 299 (`Store.swift` comments use these as examples). Turn on Family Sharing: it fits the family profiles story.

| Locale | Display name (30) | Description (45) |
|---|---|---|
| English (U.S.) | Floor Age Plus | Family profiles, plan, food photos and sleep |
| Hindi | Floor Age Plus | फ़ैमिली प्रोफ़ाइल, प्लान, फ़ोटो कैलोरी, नींद |
| Spanish (Mexico) | Floor Age Plus | Perfiles familiares, plan, fotos y sueño |
| Spanish (Spain) | Floor Age Plus | Perfiles familiares, plan, fotos y sueño |

(Lengths: 44, 43, 40 and 40 characters.)

Review screenshot for the IAP: the Plus screen, `-demoScreen plus -demoPlus NO`. Review notes for the IAP: "Unlocks the weekly training plan, food photo calories, sleep, the pelvic floor programme, the Floor Age history chart and family profiles. One-time purchase, no subscription."

---

## 6. App Review notes

Paste into App Review Information › Notes. Sign-in required: **No** (leave the demo account empty).

```
Thank you for reviewing Floor Age.

NO LOGIN. The app has no account and no server. On first launch, a short onboarding asks for a name, age and any joint limitations. Any values work.

WHAT IT IS. A home fitness app. The "Floor Age" is an estimated fitness age from four standard physical fitness tests: sit-to-rise from the floor (a well-known test from published research, Araújo et al., 2012), one-leg balance, the 30-second chair stand and a toe reach. It is a fitness estimate, not a medical device. It does not diagnose, treat or predict any condition, and the app says so on the result screen and in the safety notes.

WHERE THINGS ARE
- Today tab: "Find your Floor Age" starts the four tests. After the result, "Share my Floor Age" makes a story-sized image through the system share sheet. Today's coached session (3D coach with voice) is below it. The round avatar at the top opens Family profiles.
- Track tab: steps (Motion & Fitness), calorie log, food photo, BMI, sleep.
- Progress tab: consistency and the Floor Age history chart.
- Settings tab: profile, coach style, reminder time, Restore Purchases, Delete all my data.

CAMERA. During the Floor Age check, the camera can count chair stands, start and stop the balance timer and estimate the toe reach, using Apple's Vision body pose detection on the device. Frames are processed in memory and discarded: nothing is recorded, stored or sent. The person can always type or correct the numbers, and can deny camera access and do every test by hand. Sit-to-rise is always scored by hand. The camera is also used to photograph a meal for calorie suggestions (Vision image classification on the device; the photo is not saved).

HEALTHKIT. Read-only access to Sleep Analysis, to show nightly sleep in the Sleep screen (Track tab > Sleep, a Plus feature). The app never writes to Health, and Health data never leaves the device.

NOTIFICATIONS. One optional local evening reminder if the day's training isn't done.

IN-APP PURCHASE. "Floor Age Plus" (com.jeyaraj.floorage.plus) is a non-consumable, not a subscription. To test it, tap any locked card (for example Track > Sleep, or the Family avatar > Add a family member) or Settings > Floor Age Plus, and buy with a Sandbox account. Restore Purchases is in Settings and on the Plus screen. The Floor Age check, daily sessions, steps, calories, BMI and all safety guidance are free.

NETWORK. The only network traffic is StoreKit. Everything else works in Airplane Mode.
```

Before submitting, check the notes against the build: the exact button names for camera scoring and the share card are still being finished.

---

## 7. Screenshots

**Required size:** 6.9" iPhone portrait, **1320 × 2868** (or 1290 × 2796). App Store Connect scales these down for smaller iPhones. The app is iPhone-only (`TARGETED_DEVICE_FAMILY: 1`), so no iPad screenshots are needed. Up to 10 per locale; plan on 8. Use an iPhone 17 Pro Max / 16 Pro Max simulator (1320 × 2868).

**How to capture** (Debug build): launch with `-demoScreen <name>` (sample data, Plus unlocked), plus `-coachLook female|male`, `-voiceEnabled NO`, and `-demoSnapshot shot.png` to save and quit. For each language, add `-AppleLanguages "(hi)"` and `-AppleLocale hi_IN` (or `es_MX` / `es_ES`) so the screens are in that language too. Frame each capture with the caption headline on the warm gradient, in the matching Feature colour. Keep the text large: the first three screenshots show in search results.

| # | Screen to capture | Launch | en-US | hi | es-MX | es-ES |
|---|---|---|---|---|---|---|
| 1 | Floor Age result (big number, area gauges) | `-demoScreen result` | How old does your body move? | आपका शरीर कितने साल का है? | ¿Qué edad tiene tu cuerpo? | ¿Qué edad tiene tu cuerpo? |
| 2 | Sit-to-rise test with the coach demonstrating | `-demoScreen sitRise` | Up off the floor, no hands? | बिना हाथों के ज़मीन से उठें? | ¿Del piso sin usar las manos? | ¿Del suelo sin usar las manos? |
| 3 | Chair stand with the camera counting (pose overlay, live count) | `-demoScreen cameraChair` (scripted skeleton; a real person needs an iPhone, see note) | Your camera keeps score | कैमरा रखे आपका हिसाब | Tu cámara lleva la cuenta | La cámara lleva la cuenta |
| 4 | Today's session: 3D coach mid-move, cue on screen | `-demoScreen session` (or `today`) | A 3D coach, 10 min a day | 3D कोच, रोज़ सिर्फ़ 10 मिनट | Coach 3D, 10 minutos al día | Entrenador 3D, 10 min al día |
| 5 | Family profiles list ("Who's training?") with 3 members | `-demoScreen family` | Test your parents too | माता-पिता का भी टेस्ट करें | Evalúa también a tus papás | Evalúa también a tus padres |
| 6 | Weekly training plan | `-demoScreen plan` | A weekly plan made for you | आपके लिए हफ़्तेवार प्लान | Un plan semanal a tu medida | Un plan semanal a tu medida |
| 7 | Track tab: steps, calories, BMI | `-demoScreen track` | Steps, calories, BMI, sleep | कदम, कैलोरी, BMI और नींद | Pasos, calorías, IMC y sueño | Pasos, calorías, IMC y sueño |
| 8 | Share card on its own, tilted over a blurred chat | `-demoScreen share` | Challenge your friends | दोस्तों को चुनौती दें | Reta a tus amigos | Reta a tus amigos |

Optional small line under every caption, or a 9th slide over the Settings screen: "Private. Stays on your iPhone." / "प्राइवेट, सब कुछ iPhone पर" / "Privado: todo en tu iPhone".

Notes:
- The Simulator has no camera. `-demoScreen cameraChair` (also `cameraBalance`, `cameraReach`) plays a scripted skeleton so the screen can be captured, but a shot of a real person on a real iPhone sells better.
- `-demoScreen family` shows Priya with her parents Raj and Meena as sample members.
- Shots 5 and 6 show Plus features. The captions don't need to say "Plus", but the description does, which keeps it honest.
- Replace the placeholder demo videos before capturing anything that shows the "Watch a real demo" button.

---

## 8. App Preview video (optional, 20–30 s)

Format: 6.9" portrait, 886 × 1920 (Apple's App Preview size for this display), H.264, 30 fps, up to 30 s. Record on a device or the Simulator (`xcrun simctl io booted recordVideo`), then add the text in any editor. No voice-over; add soft music or leave it silent (autoplay is muted). The first 3 seconds must work without sound because they autoplay in search. Localise the on-screen text using the screenshot captions.

| Time | Shot | On-screen text |
|---|---|---|
| 0:00–0:03 | Real person (or the 3D coach) sitting on the floor, then standing up without hands | Can you get up without your hands? |
| 0:03–0:07 | Sit-to-rise test screen, coach demonstrating, score being set | 4 quick tests at home |
| 0:07–0:11 | Chair stand with the camera counting: pose overlay, count ticking 9, 10, 11 | Your camera keeps score |
| 0:11–0:14 | Balance test: timer starts on its own when the foot lifts | Hands-free balance timer |
| 0:14–0:17 | Result screen: Floor Age number counts up, area gauges fill | Meet your Floor Age |
| 0:17–0:21 | Today's session: coach turns as the finger drags, cue "Squeeze and lift" appears | A 3D coach, 10 min a day |
| 0:21–0:24 | Family list: switch to "Amma", her Floor Age shows | Test your parents too |
| 0:24–0:27 | Share card slides up over a chat | Challenge your friends |
| 0:27–0:30 | App icon and name on the gradient | Floor Age. Free on the App Store. Private: stays on your iPhone. |

App Review rejects previews that show things outside the app, so a real person on the floor in the first shot must be shown as part of the app (for example the in-app demo video), or start with the coach instead.

---

## 9. Launch checklist

**Accounts and agreements**
- [ ] Paid Apps Agreement signed, with bank and tax details (Business section). The IAP can't be sold without it.
- [ ] Optional: joined the App Store Small Business Program (15% commission).

**App ID and build**
- [ ] HealthKit capability enabled on the App ID `com.jeyaraj.floorage` (developer.apple.com › Identifiers). The app now also writes workouts, so App Review will see the Health write permission.
- [ ] App Group `group.com.jeyaraj.floorage` created and enabled on both `com.jeyaraj.floorage` and `com.jeyaraj.floorage.widgets` (needed for the widgets).
- [ ] App IDs exist for the widget extension (`com.jeyaraj.floorage.widgets`) and the Watch app (`com.jeyaraj.floorage.watchkitapp`); automatic signing creates them on the first TestFlight build.
- [ ] Watch app and widgets tried on real devices: chair stand counting on the wrist, balance timer, session remote, widget refresh.
- [x] `MARKETING_VERSION` in `project.yml` set to `1.0`.
- [x] `NSCameraUsageDescription` covers both meal photos and camera scoring, translated in `InfoPlist.xcstrings`.
- [x] `PrivacyInfo.xcprivacy` added (see section 2).
- [ ] Set `AppLinks.appStoreID` (`Features/Test/ShareCard.swift`) to the app's App Store ID once App Store Connect assigns it, so the share card shows a QR code and link.
- [ ] Placeholder demo videos in `FloorAge/Resources/Videos/` replaced with real clips (or removed).
- [ ] Release build tested in Airplane Mode: everything except the purchase works.
- [ ] Camera scoring tested on at least two iPhones, in good and dim light.

**In-app purchase**
- [ ] Non-consumable `com.jeyaraj.floorage.plus` created, with price, display name and description in all four languages (section 5), and a review screenshot.
- [ ] IAP attached to the 1.0 version ("In-App Purchases and Subscriptions" on the version page) and submitted with it.
- [ ] Purchase and Restore tested with a Sandbox account through TestFlight.

**Listing**
- [ ] `AppStore/privacy.html` and `AppStore/support.html` published (for example GitHub Pages from a `docs/` folder or a `gh-pages` branch) and live at the URLs in `privacy_url.txt` / `support_url.txt`. Update the URLs if the GitHub user or repo name differs.
- [ ] `python3 tools/check_appstore_metadata.py` passes.
- [ ] Hindi and Spanish store text reviewed by native speakers (Mexico and Spain separately if possible), especially the disclaimer and safety wording. The app's own translations need the same review.
- [ ] Screenshots uploaded for all four languages (section 7).
- [ ] App Privacy set to "Data Not Collected"; age rating questionnaire done (section 3).
- [ ] App Review notes pasted (section 6); sign-in required set to No.
- [ ] Availability: pick countries. English, Hindi and Spanish listings cover India, the US, Mexico, Latin America and Spain.
- [ ] Release option: "Manually release" so you can check the live page first.
