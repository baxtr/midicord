import 'package:flutter/material.dart';
import '../models/melody.dart';

class PianoRoll extends StatelessWidget {
  final List<MidiEvent> events;
  final int? playheadPosition; // current playback position in ms
  final (int, int)? selectedRange; // AB loop selection
  final Function(int, int)? onRangeSelected;
  final double pixelsPerMs;

  const PianoRoll({
    super.key,
    required this.events,
    this.playheadPosition,
    this.selectedRange,
    this.onRangeSelected,
    this.pixelsPerMs = 0.1,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text(
          'No notes recorded',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final noteOnEvents = events.where((e) => e.isNoteOn).toList();
    if (noteOnEvents.isEmpty) {
      return const Center(child: Text('No notes'));
    }

    // Calculate note range
    final notes = noteOnEvents.map((e) => e.note);
    final minNote = notes.reduce((a, b) => a < b ? a : b) - 2;
    final maxNote = notes.reduce((a, b) => a > b ? a : b) + 2;
    final noteRange = maxNote - minNote + 1;

    // Calculate duration
    final maxTimestamp = events.last.timestamp;
    final totalWidth = maxTimestamp * pixelsPerMs;

    return LayoutBuilder(
      builder: (context, constraints) {
        final noteHeight = constraints.maxHeight / noteRange;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth.clamp(constraints.maxWidth, double.infinity),
            height: constraints.maxHeight,
            child: CustomPaint(
              painter: _PianoRollPainter(
                events: noteOnEvents,
                minNote: minNote,
                maxNote: maxNote,
                noteHeight: noteHeight,
                pixelsPerMs: pixelsPerMs,
                playheadPosition: playheadPosition,
                selectedRange: selectedRange,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PianoRollPainter extends CustomPainter {
  final List<MidiEvent> events;
  final int minNote;
  final int maxNote;
  final double noteHeight;
  final double pixelsPerMs;
  final int? playheadPosition;
  final (int, int)? selectedRange;

  _PianoRollPainter({
    required this.events,
    required this.minNote,
    required this.maxNote,
    required this.noteHeight,
    required this.pixelsPerMs,
    this.playheadPosition,
    this.selectedRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF1a1a2e);
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1;
    final notePaint = Paint()..color = const Color(0xFF4fc3f7);
    final blackKeyPaint = Paint()..color = const Color(0xFF0f0f1a);
    final playheadPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    final selectionPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.2);

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw black key backgrounds
    for (int note = minNote; note <= maxNote; note++) {
      if (_isBlackKey(note)) {
        final y = (maxNote - note) * noteHeight;
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, noteHeight),
          blackKeyPaint,
        );
      }
    }

    // Draw horizontal grid lines (per note)
    for (int note = minNote; note <= maxNote; note++) {
      final y = (maxNote - note) * noteHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw vertical grid lines (per beat, assuming 120 BPM = 500ms per beat)
    const msPerBeat = 500.0;
    for (double ms = 0; ms < size.width / pixelsPerMs; ms += msPerBeat) {
      final x = ms * pixelsPerMs;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw selection
    if (selectedRange != null) {
      final x1 = selectedRange!.$1 * pixelsPerMs;
      final x2 = selectedRange!.$2 * pixelsPerMs;
      canvas.drawRect(
        Rect.fromLTRB(x1, 0, x2, size.height),
        selectionPaint,
      );
    }

    // Draw notes
    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      final x = event.timestamp * pixelsPerMs;
      final y = (maxNote - event.note) * noteHeight;

      // Find note duration (look for matching note off)
      double width = 100 * pixelsPerMs; // default 100ms
      for (int j = i + 1; j < events.length; j++) {
        // Check if there's a note-off or another note-on for same note
        if (events[j].note == event.note) {
          width = (events[j].timestamp - event.timestamp) * pixelsPerMs;
          break;
        }
      }
      width = width.clamp(4.0, double.infinity);

      // Color based on velocity
      final velocityFactor = event.velocity / 127;
      final noteColor = Color.lerp(
        const Color(0xFF4fc3f7),
        const Color(0xFFe040fb),
        velocityFactor,
      )!;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y + 1, width - 1, noteHeight - 2),
          const Radius.circular(2),
        ),
        Paint()..color = noteColor,
      );
    }

    // Draw playhead
    if (playheadPosition != null) {
      final x = playheadPosition! * pixelsPerMs;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), playheadPaint);
    }
  }

  bool _isBlackKey(int note) {
    final n = note % 12;
    return n == 1 || n == 3 || n == 6 || n == 8 || n == 10;
  }

  @override
  bool shouldRepaint(covariant _PianoRollPainter oldDelegate) {
    return oldDelegate.playheadPosition != playheadPosition ||
        oldDelegate.selectedRange != selectedRange ||
        oldDelegate.events != events;
  }
}
