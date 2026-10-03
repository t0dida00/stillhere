# StillAlive? — iOS App Build Spec

> Hand this file to Claude Code. Work **phase by phase**. After each phase: build, run tests, summarize what changed, and stop for review before starting the next phase.

## 1. Product Summary

StillAlive? is an offline-first iOS app for daily "I'm alive" check-ins between people who are apart (e.g. long-distance partners). Each user checks in at fixed times (default 9:00 and 21:00). Invited partners can see, on their own device, whether the user checked in, skipped, or missed each slot.

**Core principles**
- No sign-up or login. Identity is a generated unique ID.
- Offline-first: every action works with no network and syncs later.
- A check-in is completed by solving a random grade-3 math puzzle.
- Privacy by default: partners only see what the user explicitly shares.

## 2. Platform Constraints (read before designing)

- iOS **cannot** lock the screen or force a popup. Do NOT attempt to. The puzzle is triggered via:
  1. **Time-sensitive local notifications** at each slot time (repeat every 10 min until the grace window ends). Tapping opens the puzzle screen.
  2. **Open-app trigger**: if a slot is pending when the app opens/foregrounds, show the puzzle immediately (full-screen cover).
  3. **Optional Shortcuts automation**: Settings shows a guide for creating a Shortcuts time automation ("At 9:00 → Open App StillAlive?"). No code beyond an in-app instructions screen and an App Intent "Open Check-in".
- On iOS 26+, use **AlarmKit** for the alarm at each slot time (rings through silent mode and Focus; its "Check in" button opens the puzzle). Follow-up reminders stay as `UserNotifications`. On iOS 17–25, notifications only.
- Minimum deployment target: **iOS 17** (SwiftData).

## 3. Tech Stack

- Swift 5.9+, **SwiftUI**, **SwiftData** (local store)
- `UserNotifications`, `CoreLocation`, `AppIntents`
- Keychain (private key + user ID), iCloud Keychain sync enabled
- Backend (Phase 3+): **Supabase** (anonymous auth, Postgres, Realtime, Edge Functions, APNs push). Abstract behind a `SyncService` protocol so the app runs fully with a `NoopSyncService` until the backend exists.
- Project generation: **XcodeGen** (`project.yml`) so the project can be created from the CLI. Build with `xcodebuild`.

## 4. Data Model

```swift
enum SlotState: String, Codable { case pending, checkedIn, skipped, missed }

@Model final class LocalUser {
    var id: String            // public shareable ID (short, e.g. 8 chars base32)
    var displayName: String
    var timeZoneID: String
    var createdAt: Date
}

@Model final class CheckInSlot {
    var dayKey: String        // "yyyy-MM-dd" in the user's local time zone
    var slotIndex: Int        // 0, 1, ...
    var scheduledAt: Date     // UTC instant
    var stateRaw: String      // SlotState
    var resolvedAt: Date?
    var latitude: Double?     // only if user enabled location
    var longitude: Double?
    var synced: Bool          // false until pushed
    var ownerID: String       // LocalUser.id or partner id
}

@Model final class Partnership {
    var partnerID: String
    var partnerName: String
    var status: String        // pending, accepted, declined
    var canSeeLocation: Bool  // what *I* share with them
    var createdAt: Date
}

@Model final class AppSettings {
    var slotTimes: [Int]      // minutes from midnight, default [540, 1260]
    var graceMinutes: Int     // default 60
    var difficulty: Int       // 1...3
    var shareLocation: Bool   // default false
    var remindEveryMinutes: Int // default 10
}
```

**State rules**
- `pending` → slot time not yet resolved.
- `checkedIn` → puzzle solved correctly within the grace window.
- `skipped` → user explicitly tapped "Skip" (or swiped the check-in screen down).
- `missed` → grace window elapsed with no action. Resolve lazily on app launch/foreground and in the background task if available.
- Partners must see `skipped` and `missed` as visually different. `missed` is the high-signal state.

## 5. Identity (no login)

- On first launch generate: a short public ID (invite code) and a random private secret (32 bytes). Store both in Keychain with `kSecAttrSynchronizable = true`.
- The public ID is shared via code/QR. The secret is only used to authenticate sync requests and never leaves the Keychain except as a signature/auth token.
- Show the invite code and a QR (CoreImage `CIQRCodeGenerator`) in the Users tab.

## 6. Screens and Navigation

Tab bar (bottom): **Settings | Main | Users**

1. **Onboarding / Setup** (first launch only)
   - Generates the ID, asks for display name.
   - Permission explainer screens: Notifications (required), Location While-In-Use (optional, off by default).
2. **Main**
   - Metrics row: `Checked In: n days`, current streak, missed count.
   - Calendar (month view). Each day shows two small markers (one per slot) colored by state.
   - Segmented selector at the top: **Me** | each accepted partner. Partner calendars are read-only and update live when synced.
   - Tapping a day shows the slot details (state, time, optional location if shared).
3. **Users**
   - My invite code + QR.
   - Add partner by entering a code or scanning a QR.
   - List of partnerships with status; accept/decline incoming requests.
   - Per-partner toggle: share my location with this partner.
4. **Settings**
   - Slot times (add/remove/edit, default 9:00 and 21:00), grace window, reminder interval.
   - Puzzle difficulty.
   - Location toggle.
   - Time zone (default: device).
   - "Auto-open with Shortcuts" guide.
5. **Check-in screen** (full-screen cover)
   - Shows a random grade-3 puzzle and a numeric keypad.
   - Wrong answer: shake, let them retry (unlimited).
   - Correct answer: mark `checkedIn`, success haptic, dismiss.
   - "Skip" button, and swipe-down dismissal both record `skipped`.

## 7. Puzzle Generation

- Fully local, no network.
- Types: addition (<100), subtraction (non-negative), multiplication table (2–9), missing number (`7 + ? = 15`).
- Difficulty 1–3 widens ranges.
- Seed by `dayKey + slotIndex` (stable hash into UInt64 → SplitMix64) so reopening the app shows the same puzzle for that slot.
- Unit-test: generator is deterministic for a seed; answers are always correct; no negative results.

## 8. Notifications

- Schedule per slot, per day, for the next 7 days (iOS limit is 64 pending local notifications — reschedule on every launch and when settings change).
- On iOS 26+, an AlarmKit alarm replaces the slot-time notification when alarms are authorized; reminders continue as notifications.
- Use `interruptionLevel = .timeSensitive`. Request authorization with `.timeSensitive` where available.
- Repeat reminders every `remindEveryMinutes` until `graceMinutes` ends.
- Notification tap → deep link to the check-in screen for that slot.
- When a slot is resolved, cancel the remaining reminders for that slot.

## 9. Sync (Phase 3)

`SyncService` protocol:

```swift
protocol SyncService {
    func push(_ slots: [CheckInSlot]) async throws
    func pull(partnerID: String) async throws -> [RemoteSlot]
    func sendInvite(to partnerID: String) async throws
    func respond(to partnerID: String, accept: Bool) async throws
}
```

- Local write first, `synced = false`; a background queue retries with exponential backoff when network is reachable (`NWPathMonitor`).
- Server (Supabase): tables `users`, `partnerships`, `slots`. Row-level security so a user can only read slots of accepted partners and only write their own.
- Realtime subscription so a partner's check-in appears immediately; APNs push as fallback.
- **Missed-check-in alert**: an Edge Function (cron every few minutes) marks slots `missed` after the grace window and pushes a notification to accepted partners. This must run server-side because the phone may be off.
- Store each user's time zone; render each person's calendar in their own local day.

## 10. Project Structure

```
StillAlive/
  project.yml
  StillAlive/
    App/            StillAliveApp.swift, AppRouter.swift
    Models/         LocalUser, CheckInSlot, Partnership, AppSettings
    Services/       IdentityService, NotificationService, LocationService,
                    SlotResolver, SyncService (protocol + Noop + Supabase)
    Features/
      Onboarding/
      Main/         CalendarView, MetricsView
      Users/
      Settings/
      CheckIn/      PuzzleGenerator, CheckInView, Keypad
    Resources/
  StillAliveTests/
```

## 11. Build Phases

### Phase 1 — Local-only prototype
- [ ] Create `project.yml`, generate the Xcode project, confirm `xcodebuild` builds for the iOS Simulator.
- [ ] Models + SwiftData container.
- [ ] Identity generation + Keychain.
- [ ] Settings screen (slot times, grace, difficulty).
- [ ] Puzzle generator + unit tests.
- [ ] Check-in screen with three outcomes (checked in / skipped / missed).
- [ ] Notification scheduling and deep link to check-in.
- [ ] Main screen: metrics + calendar for "Me".
- [ ] `SlotResolver`: lazily marks expired slots as `missed`.

**Done when:** on the simulator, a slot notification opens the puzzle, solving it marks the day, and the calendar and metrics update.

### Phase 2 — Partners (local mock)
- [ ] Users tab: invite code, QR, add partner by code, list, accept/decline.
- [ ] Main screen segmented selector for partner calendars using mock data behind `SyncService`.
- [ ] Per-partner location sharing toggle.

### Phase 3 — Backend sync
- [ ] Supabase schema + RLS policies (SQL in `/backend/`).
- [ ] `SupabaseSyncService`, offline queue, realtime subscription.
- [ ] APNs push, missed-check-in Edge Function.

### Phase 4 — Polish
- [ ] Shortcuts App Intent + in-app setup guide.
- [ ] Lock Screen / Home widget showing a partner's latest check-in.
- [ ] Accessibility (Dynamic Type, VoiceOver), localization (English, Vietnamese).
- [ ] Privacy policy, App Store privacy labels, permission usage strings.

## 12. Rules for Claude Code

- Start with Phase 1 only. Ask before adding dependencies beyond what is listed.
- Keep views small; business logic lives in services and is unit-tested.
- Never block the main thread with sync or location work.
- Location is opt-in and off by default; never request it before the user enables it.
- Don't hardcode secrets. Backend keys come from an `.xcconfig` that is git-ignored.
- After each phase, run `xcodebuild test` and report results.

## 13. Open Questions (ask me before Phase 3)

1. Supabase vs CloudKit as the final backend?
2. Should a missed check-in alert partners immediately or only after both slots in a day are missed?
3. Should partners be allowed to send a "ping/are you okay?" message back?
