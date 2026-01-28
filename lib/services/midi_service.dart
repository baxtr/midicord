import 'dart:async';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import '../models/melody.dart';

class MidiService {
  final MidiCommand _midiCommand = MidiCommand();

  StreamSubscription<MidiPacket>? _midiSubscription;
  StreamSubscription<String>? _setupSubscription;

  MidiDevice? _connectedDevice;
  bool _isRecording = false;
  DateTime? _recordingStartTime;
  List<MidiEvent> _recordedEvents = [];

  // Stream controllers for UI updates
  final _connectionController = StreamController<MidiDevice?>.broadcast();
  final _midiEventController = StreamController<MidiEvent>.broadcast();
  final _recordingStateController = StreamController<bool>.broadcast();

  Stream<MidiDevice?> get connectionStream => _connectionController.stream;
  Stream<MidiEvent> get midiEventStream => _midiEventController.stream;
  Stream<bool> get recordingStateStream => _recordingStateController.stream;

  MidiDevice? get connectedDevice => _connectedDevice;
  bool get isRecording => _isRecording;
  bool get isConnected => _connectedDevice != null;

  MidiService() {
    _init();
  }

  void _init() {
    // Listen for device connections/disconnections
    _setupSubscription = _midiCommand.onMidiSetupChanged?.listen((event) {
      if (event == 'deviceDisconnected') {
        _connectedDevice = null;
        _connectionController.add(null);
        stopRecording();
      }
    });
  }

  /// Get list of available MIDI devices
  Future<List<MidiDevice>> getDevices() async {
    return await _midiCommand.devices ?? [];
  }

  /// Connect to a MIDI device
  Future<bool> connect(MidiDevice device) async {
    try {
      await _midiCommand.connectToDevice(device);
      _connectedDevice = device;
      _connectionController.add(device);

      // Start listening to MIDI data
      _midiSubscription?.cancel();
      _midiSubscription = _midiCommand.onMidiDataReceived?.listen(_handleMidiData);

      return true;
    } catch (e) {
      print('Failed to connect to MIDI device: $e');
      return false;
    }
  }

  /// Disconnect from current device
  void disconnect() {
    if (_connectedDevice != null) {
      _midiCommand.disconnectDevice(_connectedDevice!);
      _connectedDevice = null;
      _connectionController.add(null);
    }
    _midiSubscription?.cancel();
    _midiSubscription = null;
    stopRecording();
  }

  void _handleMidiData(MidiPacket packet) {
    final data = packet.data;
    if (data.isEmpty) return;

    final status = data[0];
    final type = status & 0xF0;
    final channel = status & 0x0F;

    // Only process note on/off and control change
    if (type != 0x90 && type != 0x80 && type != 0xB0) return;
    if (data.length < 3) return;

    final event = MidiEvent(
      timestamp: _isRecording && _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
          : 0,
      type: type,
      channel: channel,
      data1: data[1],
      data2: data[2],
    );

    _midiEventController.add(event);

    if (_isRecording) {
      _recordedEvents.add(event);
    }
  }

  /// Start recording - called automatically when MIDI input detected
  void startRecording() {
    if (_isRecording) return;

    _isRecording = true;
    _recordingStartTime = DateTime.now();
    _recordedEvents = [];
    _recordingStateController.add(true);
  }

  /// Stop recording and return the recorded melody
  Melody? stopRecording() {
    if (!_isRecording) return null;

    _isRecording = false;
    _recordingStateController.add(false);

    if (_recordedEvents.isEmpty) return null;

    final duration = _recordedEvents.isNotEmpty
        ? _recordedEvents.last.timestamp
        : 0;

    final melody = Melody(
      title: 'Recording ${DateTime.now().toIso8601String()}',
      createdAt: _recordingStartTime ?? DateTime.now(),
      durationMs: duration,
      events: List.from(_recordedEvents),
    );

    _recordedEvents = [];
    _recordingStartTime = null;

    return melody;
  }

  /// Auto-record: start on first note, stop after silence
  Timer? _silenceTimer;
  static const _silenceThreshold = Duration(seconds: 3);

  void enableAutoRecord() {
    _midiEventController.stream.listen((event) {
      if (event.isNoteOn) {
        if (!_isRecording) {
          startRecording();
        }
        // Reset silence timer
        _silenceTimer?.cancel();
        _silenceTimer = Timer(_silenceThreshold, () {
          stopRecording();
        });
      }
    });
  }

  void dispose() {
    _midiSubscription?.cancel();
    _setupSubscription?.cancel();
    _silenceTimer?.cancel();
    _connectionController.close();
    _midiEventController.close();
    _recordingStateController.close();
  }
}
