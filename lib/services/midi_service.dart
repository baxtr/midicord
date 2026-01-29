import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/melody.dart';

class MidiService {
  final MidiCommand _midiCommand = MidiCommand();

  StreamSubscription<MidiPacket>? _midiSubscription;
  StreamSubscription<String>? _setupSubscription;

  MidiDevice? _connectedDevice;
  bool _isRecording = false;
  DateTime? _recordingStartTime;
  List<MidiEvent> _recordedEvents = [];

  // Remembered devices for auto-connect
  Set<String> _rememberedDeviceIds = {};
  static const String _rememberedDevicesKey = 'remembered_midi_devices';

  // Stream controllers for UI updates
  final _connectionController = StreamController<MidiDevice?>.broadcast();
  final _midiEventController = StreamController<MidiEvent>.broadcast();
  final _recordingStateController = StreamController<bool>.broadcast();
  final _recordingCompleteController = StreamController<Melody>.broadcast();

  Stream<MidiDevice?> get connectionStream => _connectionController.stream;
  Stream<MidiEvent> get midiEventStream => _midiEventController.stream;
  Stream<bool> get recordingStateStream => _recordingStateController.stream;
  Stream<Melody> get recordingCompleteStream => _recordingCompleteController.stream;

  MidiDevice? get connectedDevice => _connectedDevice;
  bool get isRecording => _isRecording;
  bool get isConnected => _connectedDevice != null;

  /// Send MIDI data to the connected device
  void sendMidiData(int type, int channel, int data1, int data2) {
    if (_connectedDevice == null) return;

    final statusByte = type | channel;
    final data = Uint8List.fromList([statusByte, data1, data2]);
    _midiCommand.sendData(data, deviceId: _connectedDevice!.id);
  }

  /// Send a note on event
  void sendNoteOn(int note, int velocity, {int channel = 0}) {
    sendMidiData(0x90, channel, note, velocity);
  }

  /// Send a note off event
  void sendNoteOff(int note, {int channel = 0}) {
    sendMidiData(0x80, channel, note, 0);
  }

  /// Send all notes off (panic)
  void sendAllNotesOff({int channel = 0}) {
    // CC 123 = All Notes Off
    sendMidiData(0xB0, channel, 123, 0);
  }

  MidiService() {
    _init();
  }

  void _init() async {
    // Load remembered devices
    await _loadRememberedDevices();

    // Listen for device connections/disconnections
    _setupSubscription = _midiCommand.onMidiSetupChanged?.listen((event) async {
      if (event == 'deviceDisconnected') {
        _connectedDevice = null;
        _connectionController.add(null);
        stopRecording();
      } else if (event == 'deviceFound' || event == 'deviceAppeared') {
        // Try to auto-connect to remembered devices
        await _tryAutoConnect();
      }
    });

    // Initial auto-connect attempt
    await _tryAutoConnect();
  }

  /// Load remembered device IDs from storage
  Future<void> _loadRememberedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceIds = prefs.getStringList(_rememberedDevicesKey) ?? [];
    _rememberedDeviceIds = deviceIds.toSet();
    print('Loaded ${_rememberedDeviceIds.length} remembered MIDI devices');
  }

  /// Save remembered device IDs to storage
  Future<void> _saveRememberedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_rememberedDevicesKey, _rememberedDeviceIds.toList());
  }

  /// Remember a device for auto-connect
  Future<void> rememberDevice(MidiDevice device) async {
    _rememberedDeviceIds.add(device.id);
    await _saveRememberedDevices();
    print('Remembered MIDI device: ${device.name} (${device.id})');
  }

  /// Forget a device (disable auto-connect)
  Future<void> forgetDevice(MidiDevice device) async {
    _rememberedDeviceIds.remove(device.id);
    await _saveRememberedDevices();
    print('Forgot MIDI device: ${device.name} (${device.id})');
  }

  /// Forget all remembered devices
  Future<void> forgetAllDevices() async {
    _rememberedDeviceIds.clear();
    await _saveRememberedDevices();
    print('Forgot all MIDI devices');
  }

  /// Check if a device is remembered
  bool isDeviceRemembered(MidiDevice device) {
    return _rememberedDeviceIds.contains(device.id);
  }

  /// Get all remembered device IDs
  Set<String> get rememberedDeviceIds => Set.from(_rememberedDeviceIds);

  /// Try to auto-connect to any available remembered device
  Future<void> _tryAutoConnect() async {
    if (_connectedDevice != null) return; // Already connected

    final devices = await getDevices();
    for (final device in devices) {
      if (_rememberedDeviceIds.contains(device.id)) {
        print('Auto-connecting to remembered device: ${device.name}');
        final success = await connect(device, autoRemember: false);
        if (success) break;
      }
    }
  }

  /// Get list of available MIDI devices
  Future<List<MidiDevice>> getDevices() async {
    return await _midiCommand.devices ?? [];
  }

  /// Connect to a MIDI device
  /// If autoRemember is true (default), the device will be remembered for auto-connect
  Future<bool> connect(MidiDevice device, {bool autoRemember = true}) async {
    try {
      await _midiCommand.connectToDevice(device);
      _connectedDevice = device;
      _connectionController.add(device);

      // Remember this device for future auto-connect
      if (autoRemember) {
        await rememberDevice(device);
      }

      // Keep screen awake while connected to prevent recording interruption
      WakelockPlus.enable();

      // Start listening to MIDI data
      _midiSubscription?.cancel();
      _midiSubscription = _midiCommand.onMidiDataReceived?.listen(_handleMidiData);

      // Enable auto-recording
      enableAutoRecord();

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

    // Allow screen to sleep again
    WakelockPlus.disable();
  }

  void _handleMidiData(MidiPacket packet) {
    final data = packet.data;
    print('MIDI data received: $data');
    if (data.isEmpty) return;

    final status = data[0];
    final type = status & 0xF0;
    final channel = status & 0x0F;

    print('MIDI type: $type, channel: $channel');

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

    print('MIDI event created: note=${event.data1}, velocity=${event.data2}, isNoteOn=${event.isNoteOn}');
    _midiEventController.add(event);

    if (_isRecording) {
      _recordedEvents.add(event);
      print('Event added to recording. Total events: ${_recordedEvents.length}');
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
  StreamSubscription<MidiEvent>? _autoRecordSubscription;
  Duration _silenceThreshold = const Duration(seconds: 3);
  bool _autoRecordEnabled = false;

  void setSilenceThreshold(int seconds) {
    _silenceThreshold = Duration(seconds: seconds);
  }

  int get silenceThresholdSeconds => _silenceThreshold.inSeconds;

  void enableAutoRecord() {
    if (_autoRecordEnabled) return; // Already enabled
    _autoRecordEnabled = true;
    print('Auto-record enabled');

    _autoRecordSubscription?.cancel();
    _autoRecordSubscription = _midiEventController.stream.listen((event) {
      print('Auto-record got event: isNoteOn=${event.isNoteOn}');
      if (event.isNoteOn) {
        if (!_isRecording) {
          print('Starting recording from auto-record');
          startRecording();
        }
        // Reset silence timer
        _silenceTimer?.cancel();
        _silenceTimer = Timer(_silenceThreshold, () {
          print('Silence timer triggered, stopping recording');
          final melody = stopRecording();
          if (melody != null) {
            print('Emitting completed recording with ${melody.events.length} events');
            _recordingCompleteController.add(melody);
          }
        });
      }
    });
  }

  void dispose() {
    _midiSubscription?.cancel();
    _setupSubscription?.cancel();
    _autoRecordSubscription?.cancel();
    _silenceTimer?.cancel();
    _connectionController.close();
    _midiEventController.close();
    _recordingStateController.close();
    _recordingCompleteController.close();
    WakelockPlus.disable();
  }
}
