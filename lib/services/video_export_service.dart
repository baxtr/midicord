import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/melody.dart';
import 'audio_render_service.dart';

class VideoExportService {
  static const _videoChannel = MethodChannel('com.midicord/video');
  static const _shareChannel = MethodChannel('com.midicord/share');

  /// Export melody as video with falling notes visualization
  static Future<String?> exportVideo({
    required Melody melody,
    required int width,
    required int height,
    int fps = 30,
    Function(double)? onProgress,
  }) async {
    final frames = <Uint8List>[];
    final durationMs = melody.durationMs;
    final totalFrames = (durationMs / 1000 * fps).ceil();

    // Render frames
    for (int i = 0; i <= totalFrames; i++) {
      final playheadMs = (i / fps * 1000).round();
      final frame = await _renderFrame(
        melody: melody,
        playheadPosition: playheadMs,
        width: width,
        height: height,
      );
      if (frame != null) {
        frames.add(frame);
      }
      onProgress?.call(i / totalFrames * 0.8); // 80% for rendering frames
    }

    if (frames.isEmpty) {
      return null;
    }

    // Generate output path
    final docsDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${docsDir.path}/Tunoodle_video_$timestamp.mp4';

    // Render audio
    String? audioPath;
    try {
      audioPath = await _renderAudio(melody, docsDir.path);
    } catch (e) {
      print('Audio rendering failed: $e');
    }

    onProgress?.call(0.9); // 90% after audio

    // Create video
    try {
      await _videoChannel.invokeMethod('createVideo', {
        'frames': frames,
        'outputPath': outputPath,
        'audioPath': audioPath,
        'fps': fps,
        'width': width,
        'height': height,
      });

      onProgress?.call(1.0);
      return outputPath;
    } catch (e) {
      print('Video creation failed: $e');
      return null;
    }
  }

  /// Render a single frame of the falling notes visualization
  static Future<Uint8List?> _renderFrame({
    required Melody melody,
    required int playheadPosition,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw the falling notes visualization
    _drawFallingNotes(
      canvas: canvas,
      size: Size(width.toDouble(), height.toDouble()),
      events: melody.events,
      playheadPosition: playheadPosition,
      durationMs: melody.durationMs,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData?.buffer.asUint8List();
  }

  /// Draw falling notes visualization
  static void _drawFallingNotes({
    required Canvas canvas,
    required Size size,
    required List<MidiEvent> events,
    required int playheadPosition,
    required int durationMs,
  }) {
    const pixelsPerMs = 0.3;
    const lowestNote = 21;
    const highestNote = 108;

    // Find note range
    final noteOnEvents = events.where((e) => e.isNoteOn).toList();
    int minNote = lowestNote;
    int maxNote = highestNote;

    if (noteOnEvents.isNotEmpty) {
      final notes = noteOnEvents.map((e) => e.note);
      minNote = (notes.reduce((a, b) => a < b ? a : b) - 5).clamp(lowestNote, highestNote);
      maxNote = (notes.reduce((a, b) => a > b ? a : b) + 5).clamp(lowestNote, highestNote);
    }

    final keyCount = maxNote - minNote + 1;
    final keyWidth = size.width / keyCount;
    const pianoHeight = 60.0;
    final notesAreaHeight = size.height - pianoHeight;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0f0f1a),
    );

    // Draw vertical lanes
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    final blackKeyBgPaint = Paint()..color = const Color(0xFF0a0a12);

    for (int note = minNote; note <= maxNote; note++) {
      final x = (note - minNote) * keyWidth;
      if (_isBlackKey(note)) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, keyWidth, notesAreaHeight),
          blackKeyBgPaint,
        );
      }
      canvas.drawLine(Offset(x, 0), Offset(x, notesAreaHeight), gridPaint);
    }

    // Calculate visible time window (notes fall from top to playhead at bottom)
    final visibleDurationMs = (notesAreaHeight / pixelsPerMs).round();
    final windowStart = playheadPosition - visibleDurationMs;
    final windowEnd = playheadPosition;

    // Draw notes
    final activeNotes = <int>{};

    for (final event in noteOnEvents) {
      if (event.note < minNote || event.note > maxNote) continue;

      // Find note duration
      double duration = 200;
      for (final offEvent in events) {
        if (offEvent.isNoteOff &&
            offEvent.note == event.note &&
            offEvent.timestamp > event.timestamp) {
          duration = (offEvent.timestamp - event.timestamp).toDouble();
          break;
        }
      }

      final noteEnd = event.timestamp + duration.round();

      // Check if note is visible
      if (noteEnd < windowStart || event.timestamp > windowEnd) continue;

      // Check if note is currently playing
      if (event.timestamp <= playheadPosition && noteEnd > playheadPosition) {
        activeNotes.add(event.note);
      }

      final x = (event.note - minNote) * keyWidth;

      // Y position: notes fall down, playhead is at bottom of notes area
      final yBottom = notesAreaHeight - (event.timestamp - windowStart) * pixelsPerMs;
      final noteHeight = (duration * pixelsPerMs).clamp(8.0, double.infinity);
      final yTop = yBottom - noteHeight;

      // Color based on velocity
      final velocityFactor = event.velocity / 127;
      final noteColor = Color.lerp(
        const Color(0xFF4fc3f7),
        const Color(0xFFe040fb),
        velocityFactor,
      )!;

      final notePaint = Paint()..color = noteColor;
      final noteRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 2, yTop, keyWidth - 4, noteHeight - 2),
        const Radius.circular(4),
      );
      canvas.drawRRect(noteRect, notePaint);
    }

    // Draw playhead line at bottom of notes area
    final playheadPaint = Paint()
      ..color = const Color(0xFF4fc3f7)
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(0, notesAreaHeight),
      Offset(size.width, notesAreaHeight),
      playheadPaint,
    );

    // Draw piano keyboard
    _drawPianoKeyboard(
      canvas: canvas,
      top: notesAreaHeight,
      width: size.width,
      height: pianoHeight,
      minNote: minNote,
      maxNote: maxNote,
      keyWidth: keyWidth,
      activeNotes: activeNotes,
    );
  }

  static void _drawPianoKeyboard({
    required Canvas canvas,
    required double top,
    required double width,
    required double height,
    required int minNote,
    required int maxNote,
    required double keyWidth,
    required Set<int> activeNotes,
  }) {
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
          Rect.fromLTWH(x, top, keyWidth, height),
          isActive ? activeKeyPaint : whiteKeyPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(x, top, keyWidth, height),
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
        final blackKeyHeight = height * 0.6;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x + (keyWidth - blackKeyWidth) / 2,
              top,
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

  static bool _isBlackKey(int note) {
    final n = note % 12;
    return n == 1 || n == 3 || n == 6 || n == 8 || n == 10;
  }

  /// Render audio to WAV file using synth
  static Future<String?> _renderAudio(Melody melody, String directory) async {
    try {
      final audioPath = '$directory/temp_audio_${DateTime.now().millisecondsSinceEpoch}.wav';
      return await AudioRenderService.renderToWav(
        melody: melody,
        outputPath: audioPath,
      );
    } catch (e) {
      print('Audio rendering failed: $e');
      return null;
    }
  }

  /// Share the exported video
  static Future<void> shareVideo(String videoPath) async {
    await _shareChannel.invokeMethod('shareFile', {'path': videoPath});
  }
}
