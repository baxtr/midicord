# Midicord

A friction-free MIDI recorder app with AI melody expansion.

## Features

- **Auto-record**: Starts recording when you play, stops after silence
- **Practice diary**: GitHub-style heatmap of your practice sessions
- **Piano roll visualization**: See your recordings visually
- **AB looping & speed control**: Practice tools built-in
- **AI expansion**: Use AI to harmonize, continue, or create variations of your melodies

## Setup

1. Install Flutter: https://flutter.dev/docs/get-started/install
2. Clone this repo
3. Run `flutter pub get`
4. Connect your MIDI device via USB
5. Run `flutter run`

## Configuration

For AI features, you'll need an OpenRouter API key:
1. Get a key at https://openrouter.ai/
2. Open the app settings and enter your API key

## Tech Stack

- Flutter (cross-platform iOS/Android)
- flutter_midi_command (MIDI I/O)
- sqflite (local storage)
- OpenRouter API (AI features)
