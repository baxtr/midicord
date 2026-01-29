import 'dart:async';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

class SynthService {
  final MidiPro _midiPro = MidiPro();
  bool _isLoaded = false;
  bool _isInitializing = false;
  int _sfId = -1;
  final List<Timer> _scheduledTimers = [];

  bool get isLoaded => _isLoaded;

  Future<void> init() async {
    if (_isLoaded || _isInitializing) return;
    _isInitializing = true;

    try {
      print('SynthService: Loading soundfont...');

      // Load soundfont from assets using the asset loader
      _sfId = await _midiPro.loadSoundfontAsset(
        assetPath: 'assets/YDP-GrandPiano-20160804.sf2',
        bank: 0,
        program: 0,
      );

      _isLoaded = true;
      print('SynthService: Soundfont loaded successfully (id=$_sfId)');
    } catch (e) {
      print('SynthService: Failed to load soundfont: $e');
    }
    _isInitializing = false;
  }

  /// Play a note with given velocity
  void playNote(int note, int velocity) {
    if (!_isLoaded) return;
    _midiPro.playNote(key: note, velocity: velocity, sfId: _sfId);
  }

  /// Stop a note
  void stopNote(int note) {
    if (!_isLoaded) return;
    _midiPro.stopNote(key: note, sfId: _sfId);
  }

  /// Stop all notes
  void stopAllNotes() {
    if (!_isLoaded) return;
    _midiPro.stopAllNotes(sfId: _sfId);
  }

  /// Alias for live monitoring - just plays the note
  void monitorNoteOn(int note, int velocity) {
    playNote(note, velocity);
  }

  /// Alias for live monitoring - just stops the note
  void monitorNoteOff(int note) {
    stopNote(note);
  }

  /// Start monitoring (no-op for flutter_midi_pro, it's always ready)
  Future<void> startMonitoring() async {
    // No special setup needed - just ensure soundfont is loaded
    if (!_isLoaded) {
      await init();
    }
    print('SynthService: Monitoring started');
  }

  /// Stop monitoring
  void stopMonitoring() {
    stopAllNotes();
    print('SynthService: Monitoring stopped');
  }

  bool get isMonitoring => _isLoaded;

  /// Play a melody through the speaker (pre-render approach for smooth playback)
  /// For recorded playback, we'll schedule note events with timers
  Future<void> playMelody(List<dynamic> events, int durationMs) async {
    if (!_isLoaded) {
      print('SynthService: Cannot play melody - not loaded');
      return;
    }

    print('SynthService: Playing melody (${events.length} events, ${durationMs}ms)');

    // Cancel any existing scheduled timers
    stopMelody();

    // Schedule all note events
    for (final event in events) {
      final timestamp = event.timestamp as int;
      final type = event.type as int;
      final note = event.data1 as int;
      final velocity = event.data2 as int;

      // Schedule the event and track the timer
      final timer = Timer(Duration(milliseconds: timestamp), () {
        if (type == 0x90 && velocity > 0) {
          playNote(note, velocity);
        } else if (type == 0x80 || (type == 0x90 && velocity == 0)) {
          stopNote(note);
        }
      });
      _scheduledTimers.add(timer);
    }
  }

  /// Stop melody playback
  void stopMelody() {
    // Cancel all scheduled timers
    for (final timer in _scheduledTimers) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    stopAllNotes();
  }

  void dispose() {
    stopAllNotes();
  }
}
