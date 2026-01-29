import 'dart:typed_data';
import '../models/melody.dart';

/// Service for exporting melodies to standard MIDI file format
class MidiExportService {
  static const int _ppq = 480; // Pulses (ticks) per quarter note
  static const int _defaultTempo = 500000; // Microseconds per quarter note (120 BPM)

  /// Convert a Melody to a standard MIDI file (Type 0 - single track)
  static Uint8List exportToMidi(Melody melody) {
    final trackData = _buildTrackData(melody.events);
    final headerChunk = _buildHeaderChunk(1); // 1 track
    final trackChunk = _buildTrackChunk(trackData);

    // Combine header and track
    final result = BytesBuilder();
    result.add(headerChunk);
    result.add(trackChunk);

    return result.toBytes();
  }

  /// Build MIDI header chunk
  static Uint8List _buildHeaderChunk(int numTracks) {
    final builder = BytesBuilder();

    // "MThd"
    builder.add([0x4D, 0x54, 0x68, 0x64]);

    // Header length (always 6)
    builder.add(_toBytes32(6));

    // Format type (0 = single track)
    builder.add(_toBytes16(0));

    // Number of tracks
    builder.add(_toBytes16(numTracks));

    // Time division (ticks per quarter note)
    builder.add(_toBytes16(_ppq));

    return builder.toBytes();
  }

  /// Build MIDI track chunk
  static Uint8List _buildTrackChunk(Uint8List trackData) {
    final builder = BytesBuilder();

    // "MTrk"
    builder.add([0x4D, 0x54, 0x72, 0x6B]);

    // Track length
    builder.add(_toBytes32(trackData.length));

    // Track data
    builder.add(trackData);

    return builder.toBytes();
  }

  /// Build track data from MIDI events
  static Uint8List _buildTrackData(List<MidiEvent> events) {
    final builder = BytesBuilder();

    // Set tempo meta event at the beginning
    builder.add(_writeVariableLength(0)); // Delta time 0
    builder.add([0xFF, 0x51, 0x03]); // Tempo meta event
    builder.add([
      (_defaultTempo >> 16) & 0xFF,
      (_defaultTempo >> 8) & 0xFF,
      _defaultTempo & 0xFF,
    ]);

    // Sort events by timestamp
    final sortedEvents = List<MidiEvent>.from(events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    int lastTick = 0;

    for (final event in sortedEvents) {
      // Convert milliseconds to ticks
      // At 120 BPM: 1 quarter = 500ms, so ticks = ms * ppq / 500
      final tick = (event.timestamp * _ppq / 500).round();
      final deltaTick = tick - lastTick;
      lastTick = tick;

      // Write delta time
      builder.add(_writeVariableLength(deltaTick));

      // Write MIDI event
      final status = event.type | event.channel;
      builder.add([status, event.data1, event.data2]);
    }

    // End of track meta event
    builder.add(_writeVariableLength(0));
    builder.add([0xFF, 0x2F, 0x00]);

    return builder.toBytes();
  }

  /// Write a variable-length quantity (VLQ)
  static Uint8List _writeVariableLength(int value) {
    if (value < 0) value = 0;

    final bytes = <int>[];
    bytes.add(value & 0x7F);

    while ((value >>= 7) > 0) {
      bytes.insert(0, (value & 0x7F) | 0x80);
    }

    return Uint8List.fromList(bytes);
  }

  /// Convert int to 4 bytes (big endian)
  static Uint8List _toBytes32(int value) {
    return Uint8List.fromList([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  /// Convert int to 2 bytes (big endian)
  static Uint8List _toBytes16(int value) {
    return Uint8List.fromList([
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  /// Generate a filename for the MIDI export
  static String generateFilename(Melody melody) {
    final date = melody.createdAt;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}';
    return 'Midicord_${dateStr}_$timeStr.mid';
  }
}
