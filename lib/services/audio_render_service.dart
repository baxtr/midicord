import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';
import '../models/melody.dart';

class AudioRenderService {
  static const int _sampleRate = 44100;
  static const int _channels = 2; // Stereo

  /// Render a melody to a WAV file
  static Future<String?> renderToWav({
    required Melody melody,
    required String outputPath,
  }) async {
    try {
      // Load soundfont
      final sfData = await rootBundle.load('assets/YDP-GrandPiano-20160804.sf2');

      // Create synthesizer with settings
      final settings = SynthesizerSettings(
        sampleRate: _sampleRate,
        blockSize: 64,
        maximumPolyphony: 64,
        enableReverbAndChorus: true,
      );

      final synth = Synthesizer.loadByteData(sfData, settings);

      // Calculate total samples needed
      final durationSeconds = (melody.durationMs + 2000) / 1000.0; // Add 2 sec for release
      final totalSamples = (durationSeconds * _sampleRate).ceil();

      // Prepare output buffers
      final leftBuffer = Float32List(totalSamples);
      final rightBuffer = Float32List(totalSamples);

      // Sort events by timestamp
      final events = List<MidiEvent>.from(melody.events)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Render audio block by block
      int currentSample = 0;
      int eventIndex = 0;
      final blockSize = settings.blockSize;

      final blockLeft = Float32List(blockSize);
      final blockRight = Float32List(blockSize);

      while (currentSample < totalSamples) {
        final currentTimeMs = (currentSample / _sampleRate * 1000).round();

        // Process MIDI events up to current time
        while (eventIndex < events.length &&
            events[eventIndex].timestamp <= currentTimeMs) {
          final event = events[eventIndex];
          if (event.isNoteOn) {
            synth.noteOn(channel: event.channel, key: event.note, velocity: event.velocity);
          } else if (event.isNoteOff) {
            synth.noteOff(channel: event.channel, key: event.note);
          }
          eventIndex++;
        }

        // Render a block
        synth.render(blockLeft, blockRight);

        // Copy to output buffers
        final samplesToWrite = (currentSample + blockSize <= totalSamples)
            ? blockSize
            : totalSamples - currentSample;

        for (int i = 0; i < samplesToWrite; i++) {
          leftBuffer[currentSample + i] = blockLeft[i];
          rightBuffer[currentSample + i] = blockRight[i];
        }

        currentSample += blockSize;
      }

      // Convert to interleaved 16-bit PCM
      final pcmData = _convertToInt16Pcm(leftBuffer, rightBuffer);

      // Write WAV file
      final wavData = _createWavFile(pcmData, _sampleRate, _channels);
      final file = File(outputPath);
      await file.writeAsBytes(wavData);

      return outputPath;
    } catch (e) {
      print('Audio render error: $e');
      return null;
    }
  }

  /// Convert float buffers to interleaved 16-bit PCM
  static Uint8List _convertToInt16Pcm(Float32List left, Float32List right) {
    final length = left.length;
    final pcm = ByteData(length * 2 * 2); // 2 channels, 2 bytes per sample

    for (int i = 0; i < length; i++) {
      // Clamp and convert to 16-bit
      final leftSample = (left[i].clamp(-1.0, 1.0) * 32767).round();
      final rightSample = (right[i].clamp(-1.0, 1.0) * 32767).round();

      // Interleave: L, R, L, R...
      pcm.setInt16(i * 4, leftSample, Endian.little);
      pcm.setInt16(i * 4 + 2, rightSample, Endian.little);
    }

    return pcm.buffer.asUint8List();
  }

  /// Create a WAV file with header
  static Uint8List _createWavFile(Uint8List pcmData, int sampleRate, int channels) {
    final byteRate = sampleRate * channels * 2; // 16-bit = 2 bytes
    final blockAlign = channels * 2;
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
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, 16, Endian.little); // BitsPerSample

    // data chunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    // Combine header and data
    final result = Uint8List(44 + dataSize);
    result.setRange(0, 44, header.buffer.asUint8List());
    result.setRange(44, 44 + dataSize, pcmData);

    return result;
  }
}
