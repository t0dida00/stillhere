# Still Here

**A tiny daily check-in so the people you love know you're okay.**

Still Here is an offline-first iOS app for people who live apart: long-distance partners, parents and their grown-up children, friends abroad. At your check-in time an alarm rings and you solve a quick math puzzle to say *"I'm still here."* Your partners see each check-in on their calendar. If you miss one, they're notified and can ask you to check in. There's no sign-up: your identity is an invite code kept in iCloud Keychain.

> Formerly "StillAlive?". The bundle ID (`dev.khoa.stillalive`), Xcode project and module (`StillAlive`) keep the old name on purpose.

---

## Features

### Check-ins
- **Alarm at check-in time** (iOS 26+, AlarmKit). It rings through silent mode and Focus. Its *Check in* button opens the puzzle. On iOS 17–25, notifications are used instead.
- **Puzzle check-in.** A grade-3 math puzzle on a full-screen keypad, the same puzzle for each slot every time. You can also **skip** a check-in. If you do nothing before the grace window ends (1 hour by default), it counts as **missed**.
- **Reminders** every few minutes until you check in or the grace window ends.
- **Calendar.** Each date has a ring with one segment per check-in (green checked in, orange skipped, red missed). Decided days get a green or red background.
- **Metrics:** checked-in days, current streak and missed check-ins. Skips keep your streak; misses break it.
- **Shortcuts and Siri:** an *Open Check-in* action for Time of Day automations, and "Check in with Still Here".

### Partners
- **Invite by code or QR code** (`stillhere://invite/<code>`). Scanning with the Camera app opens Add partner directly.
- **Requests:** accept or decline invitations. You can also give partners nicknames, and everyone has an avatar.
- **Partners on your calendar.** A small avatar with that partner's own ring appears under each date. Each partner also has a full calendar, metrics and last location.
- **Missed check-in notifications** for every check-in a partner misses, plus a **Notifications** tab that keeps the history.
- **Request a check-in.** When a partner missed their latest check-in, hold a red button for 3 seconds to ask them to check in.
- **Incoming requests.** When a partner asks you, you get a notification and the puzzle pops up as soon as you open the app.
- **Emergency contacts** (Phone, Zalo, WhatsApp, Telegram). Press and hold a partner's avatar to see theirs, copy them, or call or chat.

### Location and map
- **Opt-in location**, off by default, with a per-partner *Share my location* switch.
- **Last location** card with a map, a place name and **Open in Maps**. It refreshes every 5 minutes while the app is open.
- **3D globe map** of you and every partner who shares their location. Tap someone to fly to them, and switch between Standard and Satellite.

### Everything else
- **Languages:** English and Vietnamese, including permission prompts, with an in-app language shortcut.
- **FAQ** in Settings, searchable.
- **Animated opening screen.**
- **Free-plan limits** (`PlanLimits`): 1 partner, 2 emergency contacts, 1 check-in time. *Upgrade to Premium* is a placeholder for now.

---

## Tech stack

| Area | Technology |
|---|---|
| Language and UI | Swift 5.9+, SwiftUI, Observation |
| Storage | SwiftData (local, offline-first); Keychain with iCloud sync for identity |
| Alerts | AlarmKit (iOS 26+), UserNotifications (time-sensitive) |
| Location and maps | CoreLocation, MapKit (3D globe, `CLGeocoder` place names) |
| Camera and codes | VisionKit `DataScannerViewController`, CoreImage QR generator |
| System integration | App Intents (Shortcuts and Siri), custom URL scheme `stillhere://` |
| Localization | String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`) |
| Project | XcodeGen (`project.yml`), `xcodebuild`, XCTest |
| Backend (planned) | Supabase (Postgres + row-level security, Realtime, Edge Functions) and APNs, behind the `SyncService` protocol |

Deployment target **iOS 17**. AlarmKit features turn on automatically on iOS 26 and later.

---

## Project status

| Area | Status |
|---|---|
| Check-ins, alarms, reminders, calendar, metrics | ✅ Working on device |
| Partners UI, requests, notifications, map, emergency contacts | ✅ Working, but **partner data is simulated** (`MockSyncService`) |
| QR invites, Shortcuts and Siri, Vietnamese, FAQ | ✅ Done |
| Real sync between phones (Supabase) | ⏳ Planned. Needs the backend and a paid Apple Developer account for push |
| Server push for missed check-ins and requests (works when the app is closed) | ⏳ Planned |
| Home and Lock Screen widget, accessibility pass, App Store privacy material | ⏳ Planned |

**What "simulated" means:** each partner gets about 60 days of made-up history, the same every launch. Invites you send are accepted after a few seconds. Partners whose code ends in a digit share their location. Everything a partner does goes through `SyncService`, so the real backend can replace `MockSyncService` without changing the UI.

The full product spec, with screens, rules, phases and open questions, is in [docs/SPEC.md](docs/SPEC.md).

---

## Getting started

### Requirements
- macOS with **Xcode 26 or later** (iOS 26 SDK, for AlarmKit). Full Xcode is required; the Command Line Tools alone aren't enough.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Install and run
The `.xcodeproj` is generated and git-ignored, so create it first:

```sh
git clone https://github.com/t0dida00/stillhere.git
cd stillhere
xcodegen generate          # rerun after adding or removing files, or editing project.yml
open StillAlive.xcodeproj  # then choose a simulator and press Run
```

From the command line:

```sh
xcodebuild -scheme StillAlive -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -scheme StillAlive -destination 'platform=iOS Simulator,name=iPhone 15' test
# One test class:
xcodebuild -scheme StillAlive -destination 'platform=iOS Simulator,name=iPhone 15' test -only-testing:StillAliveTests/SlotResolverTests
```

### Run on an iPhone
1. In Xcode, sign in under Settings → Accounts, then pick your team in the target's *Signing & Capabilities*.
2. On the iPhone, turn on Developer Mode. The first time, also trust the developer in Settings → General → VPN & Device Management.

**Free Personal Team:** it can't sign the Time Sensitive Notifications entitlement. Build with an empty entitlements file instead:

```sh
xcodebuild -scheme StillAlive -destination 'id=<device-udid>' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<team-id> CODE_SIGN_ENTITLEMENTS=<path/to/empty.entitlements> build
```

The empty file's plist is `<dict/>`. Personal Team builds expire after 7 days.

### Debug launch options
Debug builds accept these options for testing partners:

| Option | Effect |
|---|---|
| `-mockPartner "Dad@04:28/1"` | Adds an accepted partner "Dad" who checks in daily at 04:28 with a 1-minute grace window and misses every check-in from today. You can repeat it for more partners. |
| `-mockCheckInRequest "Dad"` | Makes the partner called Dad ask you to check in. |

```sh
xcrun devicectl device process launch --device <udid> dev.khoa.stillalive -- -mockCheckInRequest "Dad"
```

---

## Project structure

```
project.yml                 XcodeGen spec (targets, Info.plist keys, URL schemes)
StillAlive/
  App/                      App entry, RootView refresh loop, AppRouter, Shortcuts intent
  Models/                   SwiftData models: LocalUser, CheckInSlot, Partnership, AppSettings,
                            AlertRecord, CheckInRequest; EmergencyContact, PlanLimits
  Services/                 SlotSchedule (pure rules), SlotResolver, CheckInService,
                            Notification/Alarm/Location services, PartnerAlertService,
                            CheckInRequestService, SyncService (+ MockSyncService), MockScenario
  Features/                 CheckIn, Main (Check-In tab), Map, Notifications, Users,
                            Settings, Onboarding, Launch, Premium
  Resources/                Assets, Localizable.xcstrings, InfoPlist.xcstrings
StillAliveTests/            Unit tests for scheduling, metrics, notifications, sync rules, limits
docs/SPEC.md                Product spec and roadmap
CLAUDE.md                   Architecture notes for contributors and AI assistants
```

The scheduling rules (`SlotSchedule.swift`, `NotificationPlanner`, `MetricsCalculator`, `MissedAlertRule`) are pure functions with unit tests. The SwiftData services apply them. Nothing runs in the background. The app reconciles check-ins, reschedules alarms and notifications, and checks partners each time it comes to the foreground, and every 5 minutes while it's open.

---

## How it works (reference)

- **Slots** (1 a day on the free plan) are created lazily, from the day the user was created through today, whenever the app comes to the foreground. A pending slot whose grace window has elapsed becomes `missed`.
- **Changing check-in times** updates all of today's slots if nothing today is resolved yet. Otherwise:
  - slots up to the last resolved one stay as they are;
  - new times after it apply today, with fresh slot indexes so indexes never collide;
  - earlier new times start tomorrow.
- **Alarms** (iOS 26+): one AlarmKit alarm per check-in for the next 7 days. Each replaces that check-in's slot-time notification.
- **Notifications:** one at slot time, plus reminders every N minutes until the grace window ends, for the next 7 days. They're capped at 60 (iOS allows 64), soonest first, and rescheduled on every foreground and settings change.
- **Metrics:** a *checked-in day* is one where every slot was checked in or skipped, with none missed. The *streak* counts consecutive checked-in days ending today, or yesterday while today is still in progress.
- **Partner missed check-ins:** every miss produces a notification and an entry in the Notifications tab. For now the app checks on the phone. With the backend, this becomes a server push.
- **Location:** read only while sharing is on and the app is open: on foreground, every 5 minutes, and at each check-in, with a short place name saved alongside.
- **Languages:** after adding UI text, rebuild with `SWIFT_EMIT_LOC_STRINGS=YES` and run `xcrun xcstringstool sync` on the `.stringsdata` files, then translate the new strings.

---

## Roadmap

1. **Backend sync** (Supabase): a schema with row-level security, `SupabaseSyncService`, an offline queue and realtime updates.
2. **Server push:** missed check-in alerts and check-in requests that arrive even when the app is closed.
3. **Widget** showing a partner's latest check-in on the Home and Lock Screen.
4. **Accessibility pass** (Dynamic Type, VoiceOver), privacy policy and App Store privacy labels.
5. **Premium** plan with higher limits.
