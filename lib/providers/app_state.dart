import 'package:flutter/foundation.dart';
import '../models/melody.dart';
import '../services/midi_service.dart';
import '../services/storage_service.dart';
import '../services/ai_service.dart';
import '../services/synth_service.dart';

class AppState extends ChangeNotifier {
  final MidiService midiService = MidiService();
  final StorageService storageService = StorageService();
  final AiService aiService = AiService();
  final SynthService synthService = SynthService();

  List<Melody> _melodies = [];
  Map<DateTime, int> _practiceByDay = {};
  Melody? _currentRecording;
  bool _isRecording = false;
  bool _isLoading = false;

  List<Melody> get melodies => _melodies;
  Map<DateTime, int> get practiceByDay => _practiceByDay;
  Melody? get currentRecording => _currentRecording;
  bool get isRecording => _isRecording;
  bool get isLoading => _isLoading;
  bool get isConnected => midiService.isConnected;

  AppState() {
    _init();
  }

  Future<void> _init() async {
    // Listen to recording state changes
    midiService.recordingStateStream.listen((recording) {
      _isRecording = recording;
      notifyListeners();
    });

    // Listen for completed recordings and auto-save them
    midiService.recordingCompleteStream.listen((melody) async {
      print('Auto-saving recording with ${melody.events.length} events');
      await saveMelody(melody);
    });

    // Initialize synth for speaker playback (don't await to avoid blocking)
    synthService.init();

    // Load melodies
    await loadMelodies();
    await loadPracticeData();
  }

  Future<void> loadMelodies() async {
    _isLoading = true;
    notifyListeners();

    _melodies = await storageService.getAllMelodies();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadPracticeData() async {
    final now = DateTime.now();
    final startDate = DateTime(now.year - 1, now.month, now.day);

    _practiceByDay = await storageService.getPracticeTimeByDay(
      startDate: startDate,
    );
    notifyListeners();
  }

  Future<List<Melody>> getMelodiesForDate(DateTime date) async {
    return await storageService.getMelodiesForDate(date);
  }

  Future<void> saveMelody(Melody melody) async {
    final id = await storageService.saveMelody(melody);
    await loadMelodies();
    await loadPracticeData();
  }

  Future<void> updateMelody(Melody melody) async {
    await storageService.updateMelody(melody);
    await loadMelodies();
  }

  Future<void> deleteMelody(int id) async {
    await storageService.deleteMelody(id);
    await loadMelodies();
    await loadPracticeData();
  }

  void startRecording() {
    midiService.startRecording();
  }

  Melody? stopRecording() {
    return midiService.stopRecording();
  }

  void setApiKey(String key) {
    aiService.setApiKey(key);
  }

  @override
  void dispose() {
    midiService.dispose();
    super.dispose();
  }
}
