import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/melody.dart';

class StorageService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'melodory.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE melodies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        durationMs INTEGER NOT NULL,
        notes TEXT,
        albumId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE midi_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        melodyId INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        type INTEGER NOT NULL,
        channel INTEGER NOT NULL,
        data1 INTEGER NOT NULL,
        data2 INTEGER NOT NULL,
        FOREIGN KEY (melodyId) REFERENCES melodies (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE albums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        color INTEGER
      )
    ''');

    // Index for faster date-based queries (calendar view)
    await db.execute('''
      CREATE INDEX idx_melodies_date ON melodies (createdAt)
    ''');
  }

  // === Melody CRUD ===

  Future<int> saveMelody(Melody melody) async {
    final db = await database;

    return await db.transaction((txn) async {
      // Insert melody
      final melodyId = await txn.insert('melodies', melody.toMap()..remove('id'));

      // Insert events in batches for performance
      final batch = txn.batch();
      for (final event in melody.events) {
        batch.insert('midi_events', {
          'melodyId': melodyId,
          ...event.toMap(),
        });
      }
      await batch.commit(noResult: true);

      return melodyId;
    });
  }

  Future<Melody?> getMelody(int id) async {
    final db = await database;

    final melodyMaps = await db.query(
      'melodies',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (melodyMaps.isEmpty) return null;

    final eventMaps = await db.query(
      'midi_events',
      where: 'melodyId = ?',
      whereArgs: [id],
      orderBy: 'timestamp ASC',
    );

    final events = eventMaps.map((e) => MidiEvent.fromMap(e)).toList();
    return Melody.fromMap(melodyMaps.first, events);
  }

  Future<List<Melody>> getAllMelodies() async {
    final db = await database;

    final melodyMaps = await db.query('melodies', orderBy: 'createdAt DESC');

    final melodies = <Melody>[];
    for (final map in melodyMaps) {
      final eventMaps = await db.query(
        'midi_events',
        where: 'melodyId = ?',
        whereArgs: [map['id']],
        orderBy: 'timestamp ASC',
      );
      final events = eventMaps.map((e) => MidiEvent.fromMap(e)).toList();
      melodies.add(Melody.fromMap(map, events));
    }

    return melodies;
  }

  Future<List<Melody>> getMelodiesForDate(DateTime date) async {
    final db = await database;

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final melodyMaps = await db.query(
      'melodies',
      where: 'createdAt >= ? AND createdAt < ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'createdAt ASC',
    );

    final melodies = <Melody>[];
    for (final map in melodyMaps) {
      final eventMaps = await db.query(
        'midi_events',
        where: 'melodyId = ?',
        whereArgs: [map['id']],
        orderBy: 'timestamp ASC',
      );
      final events = eventMaps.map((e) => MidiEvent.fromMap(e)).toList();
      melodies.add(Melody.fromMap(map, events));
    }

    return melodies;
  }

  /// Get practice time per day for calendar heatmap
  Future<Map<DateTime, int>> getPracticeTimeByDay({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;

    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClause = 'createdAt >= ?';
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      whereClause += whereClause.isEmpty ? 'createdAt < ?' : ' AND createdAt < ?';
      whereArgs.add(endDate.toIso8601String());
    }

    final results = await db.query(
      'melodies',
      columns: ['createdAt', 'durationMs'],
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
    );

    final practiceByDay = <DateTime, int>{};

    for (final row in results) {
      final date = DateTime.parse(row['createdAt'] as String);
      final dayKey = DateTime(date.year, date.month, date.day);
      final duration = row['durationMs'] as int;

      practiceByDay[dayKey] = (practiceByDay[dayKey] ?? 0) + duration;
    }

    return practiceByDay;
  }

  Future<void> updateMelody(Melody melody) async {
    if (melody.id == null) return;

    final db = await database;
    await db.update(
      'melodies',
      melody.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [melody.id],
    );
  }

  Future<void> deleteMelody(int id) async {
    final db = await database;
    await db.delete('melodies', where: 'id = ?', whereArgs: [id]);
    await db.delete('midi_events', where: 'melodyId = ?', whereArgs: [id]);
  }

  // === Album CRUD ===

  Future<void> saveAlbum(Album album) async {
    final db = await database;
    await db.insert('albums', album.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Album>> getAllAlbums() async {
    final db = await database;
    final maps = await db.query('albums', orderBy: 'createdAt DESC');
    return maps.map((m) => Album.fromMap(m)).toList();
  }

  Future<void> deleteAlbum(String id) async {
    final db = await database;
    await db.delete('albums', where: 'id = ?', whereArgs: [id]);
    // Remove album reference from melodies
    await db.update('melodies', {'albumId': null},
        where: 'albumId = ?', whereArgs: [id]);
  }
}
