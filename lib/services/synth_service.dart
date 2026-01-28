import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';
import 'package:just_audio/just_audio.dart';

class SynthService {
  Synthesizer? _synth;
  AudioPlayer? _player;
  bool _isLoaded = false;
  bool _isInitializing = false;
  bool _isPlaying = false;
  Timer? _renderTimer;

  // Audio settings
  static const int sampleRate = 44100;
  static const int bufferSamples = 8192;

  bool get isLoaded => _isLoaded;

  Future<void> init() async {
    if (_isLoaded || _isInitializing) return;
    _isInitializing = true;

    try {
      // Load soundfont from assets
      print('SynthService: Loading soundfont...');
      final data = await rootBundle.load('assets/YDP-GrandPiano-20160804.sf2');
      print('SynthService: Soundfont data loaded, size=${data.lengthInBytes}');

      // Create synthesizer settings
      final settings = SynthesizerSettings(
        sampleRate: sampleRate,
        blockSize: 64,
        maximumPolyphony: 32,
        enableReverbAndChorus: true,
      );

      // Create synthesizer using the factory constructor
      _synth = Synthesizer.loadByteData(data, settings);

      _player = AudioPlayer();

      _isLoaded = true;
      print('SynthService: Soundfont loaded successfully');
    } catch (e) {
      print('SynthService: Failed to load soundfont: $e');
      _synth = null;
    }
    _isInitializing = false;
  }

  void playNote(int note, int velocity) {
    // For real-time playback, just trigger the note in the synth
    // (not used for melody playback, but kept for potential live play feature)
    if (!_isLoaded || _synth == null) return;
    _synth!.noteOn(channel: 0, key: note, velocity: velocity);
  }

  void stopNote(int note) {
    if (!_isLoaded || _synth == null) return;
    _synth!.noteOff(channel: 0, key: note);
  }

  void stopAllNotes() {
    if (!_isLoaded || _synth == null) return;
    _synth!.noteOffAll(immediate: true);
    _player?.stop();
  }

  /// Pre-render an entire melody to audio and play it
  /// events: list of MIDI events with timestamp, type, data1 (note), data2 (velocity)
  /// durationMs: total duration in milliseconds
  Future<void> playMelody(List<dynamic> events, int durationMs) async {
    if (!_isLoaded || _synth == null || _player == null) {
      print('SynthService: Cannot play melody - not loaded');
      return;
    }

    print('SynthService: Pre-rendering melody (${events.length} events, ${durationMs}ms)');

    // Reset synth state
    _synth!.noteOffAll(immediate: true);
    _synth!.reset();

    // Calculate total samples needed (add 1 second for note release tails)
    final totalSamples = ((durationMs + 1000) * sampleRate) ~/ 1000;
    final samplesPerMs = sampleRate / 1000.0;

    // Render in chunks while processing MIDI events
    final allPcmData = <int>[];
    int currentSample = 0;
    int eventIndex = 0;

    final chunkSize = 1024; // samples per chunk

    while (currentSample < totalSamples) {
      // Process any MIDI events that should trigger before this chunk
      final chunkEndTimeMs = (currentSample + chunkSize) / samplesPerMs;

      while (eventIndex < events.length) {
        final event = events[eventIndex];
        final eventTimeMs = event.timestamp as int;

        if (eventTimeMs <= chunkEndTimeMs) {
          final type = event.type as int;
          final note = event.data1 as int;
          final velocity = event.data2 as int;

          if (type == 0x90 && velocity > 0) {
            _synth!.noteOn(channel: 0, key: note, velocity: velocity);
          } else if (type == 0x80 || (type == 0x90 && velocity == 0)) {
            _synth!.noteOff(channel: 0, key: note);
          }
          eventIndex++;
        } else {
          break;
        }
      }

      // Render this chunk
      final chunk = ArrayInt16.zeros(numShorts: chunkSize * 2);
      _synth!.renderInterleavedInt16(chunk);

      // Add to output
      for (int i = 0; i < chunkSize * 2; i++) {
        allPcmData.add(chunk[i]);
      }

      currentSample += chunkSize;
    }

    // Convert to bytes
    final pcmBytes = Uint8List(allPcmData.length * 2);
    final byteData = ByteData.view(pcmBytes.buffer);
    for (int i = 0; i < allPcmData.length; i++) {
      byteData.setInt16(i * 2, allPcmData[i], Endian.little);
    }

    // Create WAV and play
    final wavBytes = _createWavFile(pcmBytes, sampleRate, 2, 16);
    print('SynthService: Rendered ${wavBytes.length} bytes of audio');

    final audioSource = _WavAudioSource(wavBytes);
    await _player!.setAudioSource(audioSource);
    await _player!.seek(Duration.zero);
    _player!.play();
  }

  /// Stop melody playback
  void stopMelody() {
    _player?.stop();
    _synth?.noteOffAll(immediate: true);
  }

  /// Seek to position in currently loaded audio
  Future<void> seekTo(int positionMs) async {
    await _player?.seek(Duration(milliseconds: positionMs));
  }

  /// Check if currently playing
  bool get isCurrentlyPlaying => _player?.playing ?? false;

  /// Create a WAV file from raw PCM data
  Uint8List _createWavFile(Uint8List pcmData, int sampleRate, int channels, int bitsPerSample) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);  // 'W'
    header.setUint8(9, 0x41);  // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt chunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little);  // audio format (PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    // Combine header and data
    final wavFile = Uint8List(44 + dataSize);
    wavFile.setRange(0, 44, header.buffer.asUint8List());
    wavFile.setRange(44, 44 + dataSize, pcmData);

    return wavFile;
  }

  void dispose() {
    stopAllNotes();
    _renderTimer?.cancel();
    _renderTimer = null;
    _player?.dispose();
    _player = null;
  }
}

/// Audio source for WAV data
class _WavAudioSource extends StreamAudioSource {
  final Uint8List _wavData;

  _WavAudioSource(this._wavData);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _wavData.length;

    return StreamAudioResponse(
      sourceLength: _wavData.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_wavData.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
