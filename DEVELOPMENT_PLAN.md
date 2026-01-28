# Midicord Development Plan

## Project Overview
A friction-free MIDI recorder app with AI melody expansion. Competing with Jamcorder ($185 hardware) but as a software-only solution.

**Repo:** https://github.com/baxtr/midicord

---

## What's Built ✅

### Core Architecture
- **Flutter project** configured for iOS, Android, Web, Linux
- **State management** with Provider (`lib/providers/app_state.dart`)
- **SQLite storage** for melodies and practice data (`lib/services/storage_service.dart`)

### Services
| Service | File | Status |
|---------|------|--------|
| MIDI connection & recording | `lib/services/midi_service.dart` | ✅ Ready (uses flutter_midi_command) |
| Local storage | `lib/services/storage_service.dart` | ✅ Ready |
| AI expansion | `lib/services/ai_service.dart` | ✅ Ready (OpenRouter API) |

### Screens
| Screen | File | Status |
|--------|------|--------|
| Home (record) | `lib/screens/home_screen.dart` | ✅ UI complete |
| Diary (calendar) | `lib/screens/diary_screen.dart` | ✅ UI complete |
| Session (playback) | `lib/screens/session_screen.dart` | ✅ UI complete |
| AI Expand | `lib/screens/ai_expand_screen.dart` | ✅ UI complete |

### Widgets
| Widget | File | Purpose |
|--------|------|---------|
| Piano Roll | `lib/widgets/piano_roll.dart` | MIDI visualization |
| Practice Calendar | `lib/widgets/practice_calendar.dart` | GitHub-style heatmap |
| Live MIDI Display | `lib/widgets/live_midi_display.dart` | Real-time keyboard |

### Data Models
- `Melody` - recording with events, metadata, notes
- `MidiEvent` - individual MIDI message (note on/off, CC)
- `Album` - grouping for melodies

---

## What Needs Work 🔧

### Priority 1: iOS Setup & Testing
```bash
# On Mac:
git clone https://github.com/baxtr/midicord.git
cd midicord
flutter pub get
open ios/Runner.xcworkspace
```

1. **Configure signing** in Xcode (Team, Bundle ID)
2. **Test MIDI connection** with a real USB MIDI device
3. **Fix any iOS-specific issues** with flutter_midi_command

### Priority 2: MIDI Playback
Currently playback only works if piano is connected. Add software synth:

```yaml
# Add to pubspec.yaml:
dependencies:
  flutter_midi_pro: ^3.1.6
```

Then update `lib/services/playback_service.dart` (new file needed):
- Load a SoundFont file (.sf2)
- Play MIDI events through software synth
- Allow switching between device/software playback

**SoundFont options:**
- [FluidR3_GM.sf2](https://member.keymusician.com/Member/FluidR3_GM/index.html) (~150MB, full GM)
- [GeneralUser GS](https://schristiancollins.com/generaluser.php) (~30MB, good piano)
- Custom piano-only SF2 (~10MB)

### Priority 3: Complete Features

#### AB Looping (partial)
- `lib/screens/session_screen.dart:_setLoopRange()` needs visual selection
- Let user drag on piano roll to select range

#### MIDI Export
- Add export to standard MIDI file (.mid)
- Share via iOS share sheet

#### Settings Persistence
- Store OpenRouter API key securely (flutter_secure_storage)
- Remember playback preferences

### Priority 4: Polish

#### UI Improvements
- Loading states
- Error handling with user-friendly messages
- Onboarding flow for first launch
- Empty states

#### Performance
- Lazy load melodies in diary view
- Optimize piano roll for long recordings

---

## AI Features (via OpenRouter)

### Current Implementation
```dart
// lib/services/ai_service.dart
enum ExpansionType {
  harmonize,      // Add chord tones
  continue_,      // Extend melody
  variation,      // Create variations
  accompaniment,  // Add left-hand pattern
}
```

### API Configuration
- Default model: `anthropic/claude-3.5-sonnet`
- User enters API key in Settings
- Key stored locally (needs secure storage)

### Potential Improvements
- Try music-specific models if available
- Add "style" parameter (jazz, classical, pop)
- Batch multiple suggestions
- Cache results

---

## Technical Notes

### MIDI Event Format
```dart
class MidiEvent {
  int timestamp;  // ms from recording start
  int type;       // 0x90=note on, 0x80=note off, 0xB0=CC
  int channel;    // 0-15
  int data1;      // note number or CC number
  int data2;      // velocity or CC value
}
```

### Database Schema
```sql
-- melodies table
id INTEGER PRIMARY KEY
title TEXT
createdAt TEXT (ISO8601)
durationMs INTEGER
notes TEXT (user diary entry)
albumId TEXT

-- midi_events table
id INTEGER PRIMARY KEY
melodyId INTEGER (FK)
timestamp INTEGER
type INTEGER
channel INTEGER
data1 INTEGER
data2 INTEGER

-- albums table
id TEXT PRIMARY KEY
name TEXT
createdAt TEXT
color INTEGER
```

### Auto-Record Logic
```dart
// In midi_service.dart
// Starts recording on first note
// Stops after 3 seconds of silence
static const _silenceThreshold = Duration(seconds: 3);
```

---

## iOS-Specific Requirements

### Info.plist Additions
May need to add for MIDI access:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Midicord uses Bluetooth for wireless MIDI devices</string>
```

### Background Audio (optional)
If you want recording to continue in background:
```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### Camera Connection Kit
USB MIDI devices connect via Lightning/USB-C adapter. No special permissions needed.

---

## Testing Checklist

### MIDI Input
- [ ] Device detection (USB MIDI keyboard)
- [ ] Note on/off events received correctly
- [ ] Velocity captured
- [ ] Pedal (CC64) captured
- [ ] Auto-record starts on play
- [ ] Auto-record stops on silence

### Recording & Storage
- [ ] Melody saved to database
- [ ] Events saved correctly
- [ ] Reload app, melodies persist
- [ ] Delete melody works

### Playback
- [ ] Piano roll displays correctly
- [ ] Playhead moves during playback
- [ ] Speed control works
- [ ] Loop function works

### Calendar
- [ ] Days with practice show color
- [ ] Color intensity matches duration
- [ ] Tap day shows recordings
- [ ] Navigate to session works

### AI Features
- [ ] API key entry works
- [ ] Expand melody returns results
- [ ] Results display in piano roll
- [ ] Save expanded melody works
- [ ] Analyze melody returns text

---

## Future Ideas

- **Cloud sync** - backup melodies to iCloud/Firebase
- **Social sharing** - share clips as video with piano roll visualization
- **MIDI file import** - load and practice existing songs
- **Metronome** - built-in click track
- **Chord detection** - show chord names in real-time
- **Practice goals** - daily/weekly targets with notifications
- **Apple Watch** - quick stats, start recording from wrist

---

## Commands Reference

```bash
# Run on iOS simulator
flutter run -d iPhone

# Run on connected iOS device
flutter run -d <device-id>

# List devices
flutter devices

# Build iOS release
flutter build ios --release

# Run tests
flutter test

# Analyze code
flutter analyze
```

---

## Resources

- [flutter_midi_command docs](https://pub.dev/packages/flutter_midi_command)
- [flutter_midi_pro docs](https://pub.dev/packages/flutter_midi_pro)
- [OpenRouter API](https://openrouter.ai/docs)
- [Core MIDI (Apple)](https://developer.apple.com/documentation/coremidi)
