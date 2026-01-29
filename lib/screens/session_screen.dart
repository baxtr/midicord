import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/melody.dart';
import '../providers/app_state.dart';
import '../widgets/piano_roll.dart';
import '../widgets/falling_notes_view.dart';
import '../services/midi_export_service.dart';
import '../services/video_export_service.dart';
import 'ai_expand_screen.dart';

class SessionScreen extends StatefulWidget {
  final Melody melody;

  const SessionScreen({super.key, required this.melody});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late Melody _melody;
  bool _isPlaying = false;
  int _playheadPosition = 0;
  int _lastPlayheadPosition = 0;
  Timer? _playbackTimer;
  double _playbackSpeed = 1.0;
  (int, int)? _loopRange;
  bool _isLooping = false;
  bool _useSpeaker = false; // false = MIDI output, true = speaker
  bool _useFallingNotes = false; // false = piano roll, true = falling notes
  bool _isExportingVideo = false;

  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _melody = widget.melody;
    _notesController.text = _melody.notes ?? '';
    _loadOutputPreference();
  }

  Future<void> _loadOutputPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useSpeaker = prefs.getBool('use_speaker_output') ?? false;
      _useFallingNotes = prefs.getBool('use_falling_notes_view') ?? false;
    });
  }

  Future<void> _saveOutputPreference(bool useSpeaker) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_speaker_output', useSpeaker);
  }

  Future<void> _saveViewPreference(bool useFallingNotes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_falling_notes_view', useFallingNotes);
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _pause();
    } else {
      _play();
    }
  }

  void _play() async {
    final appState = context.read<AppState>();

    if (_useSpeaker) {
      // For speaker playback, pre-render the entire melody
      setState(() => _isPlaying = true);

      // Pre-render and start playback
      await appState.synthService.playMelody(_melody.events, _melody.durationMs);

      // Start visual playhead timer
      const tickMs = 16;
      _playbackTimer = Timer.periodic(
        Duration(milliseconds: tickMs),
        (timer) {
          setState(() {
            _playheadPosition += (tickMs * _playbackSpeed).round();

            if (_playheadPosition >= _melody.durationMs) {
              _pause();
              _playheadPosition = 0;
            }
          });
        },
      );
    } else {
      // For MIDI playback, send events in real-time
      setState(() => _isPlaying = true);
      _lastPlayheadPosition = _playheadPosition;

      const tickMs = 16; // ~60fps
      _playbackTimer = Timer.periodic(
        Duration(milliseconds: tickMs),
        (timer) {
          final prevPosition = _lastPlayheadPosition;

          setState(() {
            _playheadPosition += (tickMs * _playbackSpeed).round();

            // Handle looping
            if (_isLooping && _loopRange != null) {
              if (_playheadPosition >= _loopRange!.$2) {
                appState.midiService.sendAllNotesOff();
                _playheadPosition = _loopRange!.$1;
              }
            } else if (_playheadPosition >= _melody.durationMs) {
              _pause();
              _playheadPosition = 0;
              return;
            }
          });

          // Send MIDI events that fall between previous and current position
          for (final event in _melody.events) {
            if (event.timestamp > prevPosition && event.timestamp <= _playheadPosition) {
              appState.midiService.sendMidiData(
                event.type,
                event.channel,
                event.data1,
                event.data2,
              );
            }
          }

          _lastPlayheadPosition = _playheadPosition;
        },
      );
    }
  }

  void _pause() {
    _playbackTimer?.cancel();
    // Stop playback
    final appState = context.read<AppState>();
    if (_useSpeaker) {
      appState.synthService.stopMelody();
    } else {
      appState.midiService.sendAllNotesOff();
    }
    setState(() => _isPlaying = false);
  }

  void _stop() {
    _pause();
    setState(() {
      _playheadPosition = 0;
      _lastPlayheadPosition = 0;
    });
  }

  void _setLoopRange() {
    // TODO: Implement visual selection
    // For now, just toggle looping with current quarter
    if (_loopRange == null) {
      final quarter = _melody.durationMs ~/ 4;
      final currentQuarter = _playheadPosition ~/ quarter;
      setState(() {
        _loopRange = (currentQuarter * quarter, (currentQuarter + 1) * quarter);
        _isLooping = true;
      });
    } else {
      setState(() {
        _loopRange = null;
        _isLooping = false;
      });
    }
  }

  Future<void> _saveNotes() async {
    final appState = context.read<AppState>();
    final updatedMelody = _melody.copyWith(notes: _notesController.text);
    await appState.updateMelody(updatedMelody);
    setState(() => _melody = updatedMelody);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notes saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Color(0xFFe040fb)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AiExpandScreen(melody: _melody),
                ),
              );
            },
            tooltip: 'AI Expand',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share, color: Colors.white),
            tooltip: 'Export',
            color: const Color(0xFF1a1a2e),
            onSelected: (value) {
              if (value == 'midi') {
                _exportMidi();
              } else if (value == 'video') {
                _exportVideo();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'midi',
                child: Row(
                  children: [
                    Icon(Icons.music_note, color: Colors.white70, size: 20),
                    SizedBox(width: 12),
                    Text('Export MIDI', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'video',
                child: Row(
                  children: [
                    Icon(Icons.videocam, color: Colors.white70, size: 20),
                    SizedBox(width: 12),
                    Text('Export Video', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white54),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatTime(_melody.createdAt),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_melody.events.where((e) => e.isNoteOn).length} notes \u2022 ${_melody.durationFormatted}',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // View toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'View:',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() => _useFallingNotes = false);
                      _saveViewPreference(false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: !_useFallingNotes ? const Color(0xFF4fc3f7) : const Color(0xFF1a1a2e),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Roll',
                        style: TextStyle(
                          color: !_useFallingNotes ? Colors.black : Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() => _useFallingNotes = true);
                      _saveViewPreference(true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _useFallingNotes ? const Color(0xFF4fc3f7) : const Color(0xFF1a1a2e),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Falling',
                        style: TextStyle(
                          color: _useFallingNotes ? Colors.black : Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Piano roll or Falling notes view
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: _useFallingNotes
                    ? FallingNotesView(
                        events: _melody.events,
                        playheadPosition: _playheadPosition,
                        durationMs: _melody.durationMs,
                      )
                    : PianoRoll(
                        events: _melody.events,
                        playheadPosition: _playheadPosition,
                        selectedRange: _loopRange,
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Playback position
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    _formatDuration(_playheadPosition),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: _playheadPosition.toDouble(),
                      min: 0,
                      max: _melody.durationMs.toDouble(),
                      onChanged: (value) {
                        // Pause playback when seeking
                        if (_isPlaying) {
                          _pause();
                        }
                        setState(() {
                          _playheadPosition = value.round();
                          _lastPlayheadPosition = _playheadPosition;
                        });
                      },
                      activeColor: const Color(0xFF4fc3f7),
                      inactiveColor: Colors.white24,
                    ),
                  ),
                  Text(
                    _melody.durationFormatted,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Playback controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Speed control
                  PopupMenuButton<double>(
                    onSelected: (speed) {
                      setState(() => _playbackSpeed = speed);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 0.5, child: Text('0.5x')),
                      const PopupMenuItem(value: 0.75, child: Text('0.75x')),
                      const PopupMenuItem(value: 0.9, child: Text('0.9x')),
                      const PopupMenuItem(value: 1.0, child: Text('1.0x')),
                      const PopupMenuItem(value: 1.1, child: Text('1.1x')),
                      const PopupMenuItem(value: 1.25, child: Text('1.25x')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1a2e),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_playbackSpeed}x',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Stop
                  IconButton(
                    icon: const Icon(Icons.stop, color: Colors.white),
                    onPressed: _stop,
                    iconSize: 32,
                  ),

                  // Play/Pause
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF4fc3f7),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                      ),
                      onPressed: _togglePlayback,
                      iconSize: 40,
                    ),
                  ),

                  // Loop toggle
                  IconButton(
                    icon: Icon(
                      Icons.repeat,
                      color: _isLooping ? const Color(0xFF4fc3f7) : Colors.white,
                    ),
                    onPressed: _setLoopRange,
                    iconSize: 32,
                  ),
                  const SizedBox(width: 16),

                  // Speaker/MIDI toggle
                  IconButton(
                    icon: Icon(
                      _useSpeaker ? Icons.volume_up : Icons.piano,
                      color: _useSpeaker ? const Color(0xFF4fc3f7) : Colors.white,
                    ),
                    onPressed: () {
                      final newValue = !_useSpeaker;
                      setState(() => _useSpeaker = newValue);
                      _saveOutputPreference(newValue);
                    },
                    iconSize: 28,
                    tooltip: _useSpeaker ? 'Speaker (tap for MIDI)' : 'MIDI (tap for Speaker)',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Notes section
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a1a2e),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Notes',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextButton(
                          onPressed: _saveNotes,
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: TextField(
                        controller: _notesController,
                        maxLines: null,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Add notes about this session...',
                          hintStyle: TextStyle(color: Colors.white24),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $ampm';
  }

  String _formatDuration(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Delete Recording?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final appState = context.read<AppState>();
              if (_melody.id != null) {
                await appState.deleteMelody(_melody.id!);
              }
              if (mounted) {
                Navigator.pop(context); // Dialog
                Navigator.pop(context); // Screen
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  static const _shareChannel = MethodChannel('com.midicord/share');

  Future<void> _exportVideo() async {
    if (_isExportingVideo) return;

    setState(() => _isExportingVideo = true);

    // Use a ValueNotifier for progress updates
    final progressNotifier = ValueNotifier<double>(0.0);

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Exporting Video', style: TextStyle(color: Colors.white)),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4fc3f7)),
                ),
                const SizedBox(height: 16),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  progress < 0.8
                      ? 'Rendering frames...'
                      : progress < 0.9
                          ? 'Processing audio...'
                          : 'Creating video...',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    );

    try {
      // Use screen dimensions for video (portrait)
      final videoPath = await VideoExportService.exportVideo(
        melody: _melody,
        width: 720,
        height: 1280,
        fps: 30,
        onProgress: (progress) {
          progressNotifier.value = progress;
        },
      );

      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      setState(() => _isExportingVideo = false);
      progressNotifier.dispose();

      if (videoPath != null && mounted) {
        // Share the video
        await VideoExportService.shareVideo(videoPath);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video export failed')),
        );
      }
    } catch (e) {
      print('Video export error: $e');
      progressNotifier.dispose();
      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
        setState(() => _isExportingVideo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _exportMidi() async {
    try {
      // Generate MIDI file data
      final midiData = MidiExportService.exportToMidi(_melody);
      final filename = MidiExportService.generateFilename(_melody);

      // Write to documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      final filePath = '${docsDir.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(midiData);

      // Verify file was written
      if (!await file.exists()) {
        throw Exception('Failed to write MIDI file');
      }

      // Use native iOS share sheet
      await _shareChannel.invokeMethod('shareFile', {'path': filePath});

    } catch (e) {
      print('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}
