import 'dart:async';
import 'package:flutter/material.dart';
import '../models/melody.dart';
import '../services/midi_service.dart';

class LiveMidiDisplay extends StatefulWidget {
  final MidiService midiService;

  const LiveMidiDisplay({
    super.key,
    required this.midiService,
  });

  @override
  State<LiveMidiDisplay> createState() => _LiveMidiDisplayState();
}

class _LiveMidiDisplayState extends State<LiveMidiDisplay> {
  final Map<int, int> _activeNotes = {}; // note -> velocity
  StreamSubscription<MidiEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.midiService.midiEventStream.listen(_handleEvent);
  }

  void _handleEvent(MidiEvent event) {
    setState(() {
      if (event.isNoteOn) {
        _activeNotes[event.note] = event.velocity;
      } else if (event.isNoteOff) {
        _activeNotes.remove(event.note);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _KeyboardPainter(activeNotes: _activeNotes),
      child: const SizedBox(
        height: 80,
        width: double.infinity,
      ),
    );
  }
}

class _KeyboardPainter extends CustomPainter {
  final Map<int, int> activeNotes;

  // Piano range: A0 (21) to C8 (108)
  static const int startNote = 21;
  static const int endNote = 108;
  static const int whiteKeyCount = 52;

  _KeyboardPainter({required this.activeNotes});

  @override
  void paint(Canvas canvas, Size size) {
    final whiteKeyWidth = size.width / whiteKeyCount;
    final blackKeyWidth = whiteKeyWidth * 0.6;
    final blackKeyHeight = size.height * 0.6;

    final whitePaint = Paint()..color = Colors.white;
    final blackPaint = Paint()..color = Colors.black;
    final activePaint = Paint()..color = const Color(0xFF4fc3f7);
    final activeBlackPaint = Paint()..color = const Color(0xFF0288d1);
    final borderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke;

    // Draw white keys
    int whiteKeyIndex = 0;
    for (int note = startNote; note <= endNote; note++) {
      if (!_isBlackKey(note)) {
        final x = whiteKeyIndex * whiteKeyWidth;
        final isActive = activeNotes.containsKey(note);

        canvas.drawRect(
          Rect.fromLTWH(x, 0, whiteKeyWidth - 1, size.height),
          isActive ? activePaint : whitePaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(x, 0, whiteKeyWidth - 1, size.height),
          borderPaint,
        );

        whiteKeyIndex++;
      }
    }

    // Draw black keys
    whiteKeyIndex = 0;
    for (int note = startNote; note <= endNote; note++) {
      if (!_isBlackKey(note)) {
        // Check if next note is a black key
        if (note + 1 <= endNote && _isBlackKey(note + 1)) {
          final x = (whiteKeyIndex + 1) * whiteKeyWidth - blackKeyWidth / 2;
          final isActive = activeNotes.containsKey(note + 1);

          canvas.drawRect(
            Rect.fromLTWH(x, 0, blackKeyWidth, blackKeyHeight),
            isActive ? activeBlackPaint : blackPaint,
          );
        }
        whiteKeyIndex++;
      }
    }
  }

  bool _isBlackKey(int note) {
    final n = note % 12;
    return n == 1 || n == 3 || n == 6 || n == 8 || n == 10;
  }

  @override
  bool shouldRepaint(covariant _KeyboardPainter oldDelegate) {
    return oldDelegate.activeNotes.length != activeNotes.length ||
        !_mapsEqual(oldDelegate.activeNotes, activeNotes);
  }

  bool _mapsEqual(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }
}
