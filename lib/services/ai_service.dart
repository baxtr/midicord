import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/melody.dart';

enum ExpansionType {
  harmonize,
  continue_,
  variation,
  accompaniment,
  fullSong,
}

class AiService {
  final String _baseUrl = 'https://openrouter.ai/api/v1';
  String? _apiKey;
  String _model = 'google/gemini-3-flash-preview'; // Default model
  static const String _apiKeyPref = 'openrouter_api_key';

  AiService() {
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyPref);
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, key);
  }

  void setModel(String model) {
    _model = model;
  }

  /// Convert MIDI events to a text representation for the AI
  String _eventsToText(List<MidiEvent> events) {
    final buffer = StringBuffer();
    buffer.writeln('MIDI sequence (timestamp_ms, note, velocity):');

    for (final event in events) {
      if (event.isNoteOn) {
        buffer.writeln('${event.timestamp}, ${_noteToName(event.note)}, ${event.velocity}');
      }
    }

    return buffer.toString();
  }

  String _noteToName(int note) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (note ~/ 12) - 1;
    final name = names[note % 12];
    return '$name$octave';
  }

  int _nameToNote(String name) {
    const names = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4,
                   'F': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8, 'A': 9,
                   'A#': 10, 'Bb': 10, 'B': 11};

    final match = RegExp(r'([A-Ga-g][#b]?)(-?\d+)').firstMatch(name);
    if (match == null) return 60; // Default to middle C

    final noteName = match.group(1)!;
    final octave = int.parse(match.group(2)!);

    return (octave + 1) * 12 + (names[noteName] ?? 0);
  }

  /// Parse AI response back into MIDI events
  List<MidiEvent> _parseAiResponse(String response, int startTimestamp) {
    final events = <MidiEvent>[];
    final lines = response.split('\n');

    for (final line in lines) {
      final match = RegExp(r'(\d+),\s*([A-Ga-g][#b]?-?\d+),\s*(\d+)').firstMatch(line);
      if (match != null) {
        final timestamp = int.parse(match.group(1)!) + startTimestamp;
        final note = _nameToNote(match.group(2)!);
        final velocity = int.parse(match.group(3)!);

        // Note on
        events.add(MidiEvent(
          timestamp: timestamp,
          type: 0x90,
          channel: 0,
          data1: note,
          data2: velocity,
        ));

        // Note off (default duration 200ms)
        events.add(MidiEvent(
          timestamp: timestamp + 200,
          type: 0x80,
          channel: 0,
          data1: note,
          data2: 0,
        ));
      }
    }

    return events;
  }

  Future<List<MidiEvent>> expandMelody(
    List<MidiEvent> events,
    ExpansionType type,
  ) async {
    if (_apiKey == null) {
      throw Exception('API key not set. Please configure your OpenRouter API key.');
    }

    final prompt = _buildPrompt(events, type);

    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://tunoodle.app',
        'X-Title': 'Tunoodle',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {
            'role': 'system',
            'content': '''You are a music composition assistant. You help expand and develop musical ideas.
When given MIDI data, respond ONLY with MIDI data in the same format: timestamp_ms, note_name, velocity
Each line should be one note. Use standard note names (C4, D#5, etc.).
Do not include any explanation, just the MIDI data.'''
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'temperature': 0.7,
        'max_tokens': 2000,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('AI request failed: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final content = data['choices'][0]['message']['content'] as String;

    final lastTimestamp = events.isNotEmpty ? events.last.timestamp : 0;
    return _parseAiResponse(content, lastTimestamp);
  }

  String _buildPrompt(List<MidiEvent> events, ExpansionType type) {
    final midiText = _eventsToText(events);

    switch (type) {
      case ExpansionType.harmonize:
        return '''$midiText

Add harmonizing notes to this melody. For each note, suggest chord tones that would complement it.
Output the harmony notes in the same format, with timestamps aligned to the original melody.''';

      case ExpansionType.continue_:
        return '''$midiText

Continue this melody for another 8-16 bars in the same style and key.
Maintain the rhythmic and melodic character of the original.
Start the timestamps from where the original ended.''';

      case ExpansionType.variation:
        return '''$midiText

Create a variation of this melody. Keep the general contour and rhythm but:
- Add ornaments or passing tones
- Slightly modify the rhythm
- Keep it recognizable but fresh
Output with the same starting timestamp.''';

      case ExpansionType.accompaniment:
        return '''$midiText

Create a simple left-hand accompaniment pattern for this melody.
Use bass notes and chord patterns appropriate for the implied harmony.
Notes should be in a lower register (C2-C4 range).''';

      case ExpansionType.fullSong:
        return '''$midiText

Transform this melody into a complete, professional-quality piano piece:
1. First, analyze the melody and fix any notes that sound "wrong" or out of key - correct them to fit the implied harmony
2. Add an intro (4-8 bars) that sets up the melody
3. Present the main melody with proper accompaniment
4. Add a contrasting B section or development
5. Return to the main theme
6. Add an outro/ending

Make it sound polished and complete like a real piano composition.
Keep the core melody recognizable but enhance it professionally.
Include both hands - melody in the right hand range (C4-C6) and accompaniment/bass in the left hand range (C2-C4).
Output all notes in the format: timestamp_ms, note_name, velocity''';
    }
  }

  /// Analyze a melody and return insights
  Future<String> analyzeMelody(List<MidiEvent> events) async {
    if (_apiKey == null) {
      throw Exception('API key not set');
    }

    final midiText = _eventsToText(events);

    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://tunoodle.app',
        'X-Title': 'Tunoodle',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {
            'role': 'system',
            'content': 'You are a music theory expert. Analyze MIDI data and provide brief, helpful insights about the music.'
          },
          {
            'role': 'user',
            'content': '''$midiText

Briefly analyze this melody:
1. What key/scale does it seem to be in?
2. What's the general character/mood?
3. Any notable patterns or motifs?
4. One suggestion for development?

Keep the response concise (under 150 words).'''
          }
        ],
        'temperature': 0.5,
        'max_tokens': 300,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('AI request failed: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }
}
