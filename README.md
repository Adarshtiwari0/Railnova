# RailNova

A Flutter app for live Indian Railways train tracking — running status, station
boards, PNR status, and favourites — built on top of the
[RailRadar](https://railradar.in/docs) API.

<!--
  TODO: add 2-3 screenshots or a short GIF here before publishing, e.g.
  ![Live train screen](docs/screenshots/live_train.png)
-->

## Features

- **Live train tracking** — current position on a station-by-station route
  timeline, delay, and estimated distance to the next stop, auto-refreshing
  every 30s while the journey is in progress.
- **PNR status** — booking, seat/coach, and confirmation status lookup.
- **Live station board** — real-time arrivals/departures at any station,
  with an optional "going to" filter that only shows trains genuinely
  travelling in that direction (not just ones that happen to touch both
  stations on separate legs).
- **Search trains between stations**, with recent-search history.
- **Favourite trains** for one-tap access to frequently tracked trains.
- **Push notifications** for delay updates on tracked/favourited trains
  (Firebase Cloud Messaging).
- **Multiple themes/skins**, with the status bar automatically adapting to
  stay legible against light or dark skins.

## Tech stack

- **Flutter** (Android, iOS, Web, Windows, macOS, Linux)
- **Provider** for state management
- **Firebase** — Analytics, Crashlytics, Cloud Messaging
- **REST API** — [RailRadar](https://railradar.in/docs) for live train and
  station data
- **SharedPreferences** for local persistence (recent searches, favourites)

## Project structure

```
lib/
  core/
    config/      # API base URL, timeouts
    theme/       # skins / design tokens
    utils/       # shared, unit-tested helpers (e.g. delay formatting)
    widgets/     # shared widgets (route timeline, live station board, ...)
  features/
    home/        # landing screen, quick actions
    live/        # live train tracking
    pnr/         # PNR status lookup
    search/      # search trains between stations
    station_board/ # live station board
    train_details/ # static train schedule details
    train_list/  # search results list
  models/        # API response models
  services/      # HTTP + notification services
  providers/     # app-wide state (theme, etc.)
test/            # unit tests
```

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- A Firebase project (for Analytics/Crashlytics/Messaging) — optional if you
  strip those out

### Setup

1. Clone the repo and install dependencies:

   ```bash
   flutter pub get
   ```

2. **Firebase config** — this repo does *not* include Firebase client
   config files (they're project-specific and gitignored). To run with
   Firebase features working:

   - Install the [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup)
     and run `flutterfire configure` against your own Firebase project, **or**
   - Manually place `google-services.json` in `android/app/` and
     `GoogleService-Info.plist` in `ios/Runner/` (and `macos/Runner/` if
     targeting macOS), downloaded from your Firebase console.

   Without these, the app still runs — Firebase calls will just fail
   silently/log an error rather than crash.

3. **API base URL** — set in `lib/core/config/app_config.dart`. Points at a
   deployed backend by default; update it for local development against
   your own backend (see the comments in that file for emulator/device
   URLs).

4. Run it:

   ```bash
   flutter run
   ```

### Running tests

```bash
flutter test
```

## Architecture notes

- Live data (train position, delays) is polled every 30s while a live train
  screen is open. Responses carry a request sequence number so that a
  slow/out-of-order response can never overwrite fresher data already on
  screen (relevant when switching dates or stations quickly).
- Delay formatting (`Xh Ym` vs a raw minute count) lives in one place,
  `lib/core/utils/format.dart`, and is unit-tested — every screen that shows
  a delay uses it rather than reimplementing the logic.

## Roadmap / known gaps

- Only `formatDelay` has unit tests so far — widget-level tests would be a
  good next addition.
- No CI workflow yet (e.g. GitHub Actions running `flutter analyze` +
  `flutter test` on every PR).
- App icon is still the default Flutter icon — see
  [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons)
  for a quick way to set a custom one.
