# Still Here

Offline-first iOS app for daily "I'm alive" check-ins between people who are apart. Full spec: [docs/SPEC.md](docs/SPEC.md).

## Requirements

- Xcode 15+ (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Setup

The `.xcodeproj` is generated and git-ignored. After cloning, or after adding or removing files:

```sh
xcodegen generate
open StillAlive.xcodeproj
```

Build and test from the CLI:

```sh
xcodebuild -scheme StillAlive -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -scheme StillAlive -destination 'platform=iOS Simulator,name=iPhone 15' test
```

To run on a device, set your team in Xcode (Signing & Capabilities). The app uses the Time Sensitive Notifications entitlement.

## Status

Phase 1 (local-only prototype) is implemented. Phase 2 (partners) is implemented on mock data, except QR codes. Backend sync (Phase 3) and polish (Phase 4) are not. See the roadmap in [docs/SPEC.md](docs/SPEC.md) §11.

Tabs: **Map – Check-In – Notifications – Users – Settings**.

## Behaviour

- **Slots** (1 a day on the free plan) are created lazily, from the day the user was created through today, whenever the app comes to the foreground. A pending slot whose grace window has elapsed becomes `missed`.
- **Changing check-in times** updates all of today's slots if nothing today has been resolved yet. Otherwise slots up to the last resolved one stay as they are, and new times after it apply today with fresh slot indexes, so indexes never collide. Earlier new times start tomorrow.
- **Alarms** (iOS 26+): an AlarmKit alarm rings at each slot time for the next 7 days and replaces the slot-time notification. Its *Check in* button opens the puzzle.
- **Notifications**: one at slot time plus reminders every N minutes until the grace window ends, for the next 7 days. The total is capped at 60 (iOS allows 64), soonest first, and everything is rescheduled on each foreground and settings change.
- **Metrics**: a *checked-in day* is a day on which every slot was checked in or skipped, with none missed. The *streak* counts consecutive checked-in days ending today, or yesterday while today is still in progress. A miss today resets it; a skip doesn't.
- **Calendar**: each date has an outer ring with one segment per slot, in order: green = checked in, orange = skipped, red = missed, empty = still pending. Once the day is decided, the date also gets a filled background: green when every slot was checked in or skipped, red when any was missed. The day detail list shows each slot's state: filled green = checked in, filled red = missed, hollow orange = skipped, hollow grey = pending.
- **Last location**: while location sharing is on, the app saves your location and place name when it comes to the foreground and every 5 minutes while it stays open, and shows it on a map below the calendar. Check-ins also save their place name. Nothing is requested or saved while it's off, and nothing runs in the background.
- **Partners (mock)**: `MockSyncService` simulates partners until the backend exists. Invites sent by code are accepted after about 5 seconds; "Simulate an invitation" creates an incoming request. Each partner gets ~60 days of made-up check-ins in a home city that stays the same per code. Partners whose code ends in a digit share their location.
- **Free-plan limits**: 1 partner (counting sent invites), 2 emergency contacts, 1 check-in time, set in `PlanLimits`. At a limit, the add button becomes "Upgrade to Premium" (a placeholder for now); partner requests still arrive but can't be accepted. New users start with one check-in time, 09:00.
- **Users**: your avatar (photo or initial) and name are editable on Users → Me, where you can also add up to 2 emergency contacts (Phone, Zalo, WhatsApp or Telegram). Partners have avatars, nicknames (only you see them) and a per-partner "Share my location" toggle.
- **Request a check-in**: when a partner's latest check-in was missed, their Check-In view shows a red button; hold it for 3 seconds to ask them to check in (5-minute cooldown). Simulated partners don't receive it yet.
- **Incoming check-in requests**: when a partner asks you to check in, you get a notification and the puzzle pops up as soon as the app opens. Solving it answers them; "Not now" sets it aside. Debug builds can fake one with `-mockCheckInRequest "Dad"`.
- **Partner emergency contacts**: on Check-In, hold a partner's avatar for 1 second to see their emergency contacts, copy them or open the call or chat. Demo partners have 0–2 made-up contacts each.
- **Partners on my calendar**: with *Show partners* on, each date shows partners below it as small avatars inside their own ring; more than 2 collapse to one avatar plus a count. Tapping a day lists my check-ins, then each partner's.
- **Map**: a 3D globe with me and every partner who shares their location as avatar pins. Tap a person to fly to them; 3D, globe and map-type (Standard / Satellite) buttons sit in one row at the top.
- **Shortcuts and Siri**: the *Open Check-in* action opens the app on Check-In, and the puzzle appears if a check-in is due. Use it in a Time of Day automation (Settings → Auto-open with Shortcuts) or say "Check in with Still Here".
- **QR invites**: Users → Me → Show QR code encodes `stillhere://invite/<code>` (old `stillalive://` links still work). Scan it in Add partner, or with the Camera app, which opens Add partner with the code filled in.
- **FAQ**: Settings → FAQ answers common questions (check-ins, partners, privacy, plans), searchable, in both languages. Keep its answers in `Features/Settings/FAQView.swift` in step with app behaviour.
- **Languages**: English and Vietnamese, following the iPhone's language. Text lives in `StillAlive/Resources/Localizable.xcstrings` (and `InfoPlist.xcstrings` for permission prompts). After adding UI text, rebuild with `SWIFT_EMIT_LOC_STRINGS=YES` and run `xcrun xcstringstool sync` on the `.stringsdata` files to pick up new strings, then translate them.
- **Partner missed check-ins**: you get a notification for every check-in a partner misses, and tapping it opens their calendar. The Notifications tab keeps the history, with an unread badge. For now the app checks on the phone (on opening and every 5 minutes while open); with the backend it becomes a server push that arrives even when the app is closed. See [docs/SPEC.md](docs/SPEC.md) §9.
