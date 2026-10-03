# StillAlive?

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

Phase 1 (local-only prototype) is implemented. Partners (Phase 2), backend sync (Phase 3) and polish (Phase 4) are not.

## Phase 1 behaviour

- **Slots** are created lazily, from the day the user was created through today, whenever the app comes to the foreground. A pending slot whose grace window has elapsed becomes `missed`.
- **Changing check-in times** updates all of today's slots if nothing today has been resolved yet. Otherwise slots up to the last resolved one stay as they are, and new times after it apply today with fresh slot indexes, so indexes never collide. Earlier new times start tomorrow.
- **Alarms** (iOS 26+): an AlarmKit alarm rings at each slot time for the next 7 days and replaces the slot-time notification. Its *Check in* button opens the puzzle.
- **Notifications**: one at slot time plus reminders every N minutes until the grace window ends, for the next 7 days. The total is capped at 60 (iOS allows 64), soonest first, and everything is rescheduled on each foreground and settings change.
- **Metrics**: a *checked-in day* is a day on which every slot was checked in or skipped, with none missed. The *streak* counts consecutive checked-in days ending today, or yesterday while today is still in progress. A miss today resets it; a skip doesn't.
- **Calendar**: each date has an outer ring with one segment per slot, in order: green = checked in, orange = skipped, red = missed, empty = still pending. Once the day is decided, the date also gets a filled background: green when every slot was checked in or skipped, red when any was missed. The day detail list shows each slot's state: filled green = checked in, filled red = missed, hollow orange = skipped, hollow grey = pending.
- **Last location**: while location sharing is on, the app saves your location and place name each time it comes to the foreground, and shows it on a map below the calendar. Nothing is requested or saved while it's off.
