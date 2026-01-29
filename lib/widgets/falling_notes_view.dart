import 'package:flutter/material.dart';
import '../models/melody.dart';

class FallingNotesView extends StatefulWidget {
  final List<MidiEvent> events;
  final int? playheadPosition;
  final int durationMs;
  final double pixelsPerMs;

  const FallingNotesView({
    super.key,
    required this.events,
    required this.durationMs,
    this.playheadPosition,
    this.pixelsPerMs = 0.15,
  });

  @override
  State<FallingNotesView> createState() => _FallingNotesViewState();
}

class _FallingNotesViewState extends State<FallingNotesView> {
  final ScrollController _scrollController = ScrollController();
  double _viewportHeight = 0;

  // Piano key layout - 88 keys from A0 to C8
  static const int _lowestNote = 21; // A0
  static const int _highestNote = 108; // C8
  static const int _totalKeys = 88;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FallingNotesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playheadPosition != oldWidget.playheadPosition &&
        widget.playheadPosition != null &&
        _scrollController.hasClients) {
      _scrollToPlayhead();
    }
  }

  void _scrollToPlayhead() {
    final playheadY = widget.playheadPosition! * widget.pixelsPerMs;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Keep playhead near the bottom of the viewport (where the piano is)
    final targetScroll = playheadY - _viewportHeight * 0.7;

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(targetScroll.clamp(0, maxScroll));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;

        // Calculate which notes are used to determine key range
        final noteOnEvents = widget.events.where((e) => e.isNoteOn).toList();
        int minNote = _lowestNote;
        int maxNote = _highestNote;

        if (noteOnEvents.isNotEmpty) {
          final notes = noteOnEvents.map((e) => e.note);
          minNote = (notes.reduce((a, b) => a < b ? a : b) - 5).clamp(_lowestNote, _highestNote);
          maxNote = (notes.reduce((a, b) => a > b ? a : b) + 5).clamp(_lowestNote, _highestNote);
        }

        final keyCount = maxNote - minNote + 1;
        final keyWidth = constraints.maxWidth / keyCount;
        final pianoHeight = 60.0;
        final totalHeight = widget.durationMs * widget.pixelsPerMs + _viewportHeight;

        return Column(
          children: [
            // Falling notes area
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                reverse: true, // Notes fall down, so scroll from bottom
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: totalHeight,
                  child: CustomPaint(
                    painter: _FallingNotesPainter(
                      events: noteOnEvents,
                      allEvents: widget.events,
                      minNote: minNote,
                      maxNote: maxNote,
                      keyWidth: keyWidth,
                      pixelsPerMs: widget.pixelsPerMs,
                      playheadPosition: widget.playheadPosition,
                      totalHeight: totalHeight,
                      viewportHeight: _viewportHeight,
                    ),
                  ),
                ),
              ),
            ),
            // Piano keyboard
            SizedBox(
              height: pianoHeight,
              child: CustomPaint(
                size: Size(constraints.maxWidth, pianoHeight),
                painter: _PianoKeyboardPainter(
                  minNote: minNote,
                  maxNote: maxNote,
                  keyWidth: keyWidth,
                  activeNotes: _getActiveNotes(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Set<int> _getActiveNotes() {
    if (widget.playheadPosition == null) return {};

    final activeNotes = <int>{};
    final pos = widget.playheadPosition!;

    // Find notes that are currently being played
    for (final event in widget.events) {
      if (event.isNoteOn && event.timestamp <= pos) {
        // Check if there's a note-off after this
        bool stillPlaying = true;
        for (final offEvent in widget.events) {
          if (offEvent.isNoteOff &&
              offEvent.note == event.note &&
              offEvent.timestamp > event.timestamp &&
              offEvent.timestamp <= pos) {
            stillPlaying = false;
            break;
          }
        }
        if (stillPlaying) {
          activeNotes.add(event.note);
        }
      }
    }

    return activeNotes;
  }
}

class _FallingNotesPainter extends CustomPainter {
  final List<MidiEvent> events;
  final List<MidiEvent> allEvents;
  final int minNote;
  final int maxNote;
  final double keyWidth;
  final double pixelsPerMs;
  final int? playheadPosition;
  final double totalHeight;
  final double viewportHeight;

  _FallingNotesPainter({
    required this.events,
    required this.allEvents,
    required this.minNote,
    required this.maxNote,
    required this.keyWidth,
    required this.pixelsPerMs,
    required this.totalHeight,
    required this.viewportHeight,
    this.playheadPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0f0f1a);
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    final blackKeyBgPaint = Paint()..color = const Color(0xFF0a0a12);
    final playheadPaint = Paint()
      ..color = const Color(0xFF4fc3f7)
      ..strokeWidth = 3;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw vertical lanes for each key
    for (int note = minNote; note <= maxNote; note++) {
      final x = (note - minNote) * keyWidth;

      // Darker background for black keys
      if (_isBlackKey(note)) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, keyWidth, size.height),
          blackKeyBgPaint,
        );
      }

      // Vertical grid line
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    // Draw horizontal grid lines (every beat at 120 BPM)
    const msPerBeat = 500.0;
    for (double ms = 0; ms < size.height / pixelsPerMs; ms += msPerBeat) {
      final y = size.height - (ms * pixelsPerMs);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw notes
    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      if (event.note < minNote || event.note > maxNote) continue;

      final x = (event.note - minNote) * keyWidth;
      final y = size.height - (event.timestamp * pixelsPerMs);

      // Find note duration
      double duration = 200; // default 200ms
      for (final offEvent in allEvents) {
        if (offEvent.isNoteOff &&
            offEvent.note == event.note &&
            offEvent.timestamp > event.timestamp) {
          duration = (offEvent.timestamp - event.timestamp).toDouble();
          break;
        }
      }

      final noteHeight = (duration * pixelsPerMs).clamp(8.0, double.infinity);

      // Color based on velocity
      final velocityFactor = event.velocity / 127;
      final noteColor = Color.lerp(
        const Color(0xFF4fc3f7),
        const Color(0xFFe040fb),
        velocityFactor,
      )!;

      // Draw note rectangle
      final notePaint = Paint()..color = noteColor;
      final noteRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 2, y - noteHeight, keyWidth - 4, noteHeight - 2),
        const Radius.circular(4),
      );
      canvas.drawRRect(noteRect, notePaint);

      // Add subtle border
      final borderPaint = Paint()
        ..color = noteColor.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(noteRect, borderPaint);
    }

    // Draw playhead
    if (playheadPosition != null) {
      final y = size.height - (playheadPosition! * pixelsPerMs);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        playheadPaint,
      );

      // Add glow effect
      final glowPaint = Paint()
        ..color = const Color(0xFF4fc3f7).withOpacity(0.3)
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), glowPaint);
    }
  }

  bool _isBlackKey(int note) {
    final n = note % 12;
    return n == 1 || n == 3 || n == 6 || n == 8 || n == 10;
  }

  @override
  bool shouldRepaint(covariant _FallingNotesPainter oldDelegate) {
    return oldDelegate.playheadPosition != playheadPosition ||
        oldDelegate.events != events;
  }
}

class _PianoKeyboardPainter extends CustomPainter {
  final int minNote;
  final int maxNote;
  final double keyWidth;
  final Set<int> activeNotes;

  _PianoKeyboardPainter({
    required this.minNote,
    required this.maxNote,
    required this.keyWidth,
    required this.activeNotes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final whiteKeyPaint = Paint()..color = Colors.white;
    final blackKeyPaint = Paint()..color = const Color(0xFF1a1a1a);
    final activeKeyPaint = Paint()..color = const Color(0xFF4fc3f7);
    final borderPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw white keys first
    for (int note = minNote; note <= maxNote; note++) {
      if (!_isBlackKey(note)) {
        final x = (note - minNote) * keyWidth;
        final isActive = activeNotes.contains(note);

        canvas.drawRect(
          Rect.fromLTWH(x, 0, keyWidth, size.height),
          isActive ? activeKeyPaint : whiteKeyPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(x, 0, keyWidth, size.height),
          borderPaint,
        );
      }
    }

    // Draw black keys on top
    for (int note = minNote; note <= maxNote; note++) {
      if (_isBlackKey(note)) {
        final x = (note - minNote) * keyWidth;
        final isActive = activeNotes.contains(note);
        final blackKeyWidth = keyWidth * 0.7;
        final blackKeyHeight = size.height * 0.6;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x + (keyWidth - blackKeyWidth) / 2,
              0,
              blackKeyWidth,
              blackKeyHeight,
            ),
            const Radius.circular(2),
          ),
          isActive ? activeKeyPaint : blackKeyPaint,
        );
      }
    }
  }

  bool _isBlackKey(int note) {
    final n = note % 12;
    return n == 1 || n == 3 || n == 6 || n == 8 || n == 10;
  }

  @override
  bool shouldRepaint(covariant _PianoKeyboardPainter oldDelegate) {
    return oldDelegate.activeNotes != activeNotes;
  }
}
