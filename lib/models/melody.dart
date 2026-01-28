import 'dart:typed_data';

class MidiEvent {
  final int timestamp; // milliseconds from start
  final int type; // 0x90 = note on, 0x80 = note off, 0xB0 = control change
  final int channel;
  final int data1; // note number or control number
  final int data2; // velocity or control value

  MidiEvent({
    required this.timestamp,
    required this.type,
    required this.channel,
    required this.data1,
    required this.data2,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp,
        'type': type,
        'channel': channel,
        'data1': data1,
        'data2': data2,
      };

  factory MidiEvent.fromMap(Map<String, dynamic> map) => MidiEvent(
        timestamp: map['timestamp'],
        type: map['type'],
        channel: map['channel'],
        data1: map['data1'],
        data2: map['data2'],
      );

  bool get isNoteOn => type == 0x90 && data2 > 0;
  bool get isNoteOff => type == 0x80 || (type == 0x90 && data2 == 0);
  int get note => data1;
  int get velocity => data2;
}

class Melody {
  final int? id;
  final String title;
  final DateTime createdAt;
  final int durationMs;
  final List<MidiEvent> events;
  final String? notes; // user notes/diary entry
  final String? albumId;

  Melody({
    this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.events,
    this.notes,
    this.albumId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': durationMs,
        'notes': notes,
        'albumId': albumId,
      };

  factory Melody.fromMap(Map<String, dynamic> map, List<MidiEvent> events) =>
      Melody(
        id: map['id'],
        title: map['title'],
        createdAt: DateTime.parse(map['createdAt']),
        durationMs: map['durationMs'],
        events: events,
        notes: map['notes'],
        albumId: map['albumId'],
      );

  Melody copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    int? durationMs,
    List<MidiEvent>? events,
    String? notes,
    String? albumId,
  }) =>
      Melody(
        id: id ?? this.id,
        title: title ?? this.title,
        createdAt: createdAt ?? this.createdAt,
        durationMs: durationMs ?? this.durationMs,
        events: events ?? this.events,
        notes: notes ?? this.notes,
        albumId: albumId ?? this.albumId,
      );

  /// Get note range for visualization
  (int, int) get noteRange {
    if (events.isEmpty) return (60, 72);
    final notes = events.where((e) => e.isNoteOn).map((e) => e.note);
    if (notes.isEmpty) return (60, 72);
    return (notes.reduce((a, b) => a < b ? a : b),
            notes.reduce((a, b) => a > b ? a : b));
  }

  /// Duration formatted as mm:ss
  String get durationFormatted {
    final minutes = durationMs ~/ 60000;
    final seconds = (durationMs % 60000) ~/ 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class Album {
  final String id;
  final String name;
  final DateTime createdAt;
  final int? color;

  Album({
    required this.id,
    required this.name,
    required this.createdAt,
    this.color,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'color': color,
      };

  factory Album.fromMap(Map<String, dynamic> map) => Album(
        id: map['id'],
        name: map['name'],
        createdAt: DateTime.parse(map['createdAt']),
        color: map['color'],
      );
}
