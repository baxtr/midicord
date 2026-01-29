import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/melody.dart';
import '../providers/app_state.dart';
import '../services/ai_service.dart';
import '../widgets/piano_roll.dart';

class AiExpandScreen extends StatefulWidget {
  final Melody melody;

  const AiExpandScreen({super.key, required this.melody});

  @override
  State<AiExpandScreen> createState() => _AiExpandScreenState();
}

class _AiExpandScreenState extends State<AiExpandScreen> {
  List<MidiEvent> _expandedEvents = [];
  bool _isLoading = false;
  String? _error;
  String? _analysis;
  ExpansionType _selectedType = ExpansionType.continue_;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI Expand',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Original melody
              const Text(
                'Original',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: PianoRoll(events: widget.melody.events),
              ),
              const SizedBox(height: 24),

              // Expansion type selector
              const Text(
                'Expansion Type',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ExpansionType.values.map((type) {
                  final isSelected = type == _selectedType;
                  return ChoiceChip(
                    label: Text(_getTypeName(type)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedType = type);
                      }
                    },
                    backgroundColor: const Color(0xFF1a1a2e),
                    selectedColor: const Color(0xFF4fc3f7),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                _getTypeDescription(_selectedType),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 24),

              // Generate button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _expand(appState),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isLoading ? 'Generating...' : 'Generate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFe040fb),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Result
              if (_expandedEvents.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Generated',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_arrow,
                              color: Color(0xFF4fc3f7)),
                          onPressed: _playExpanded,
                          tooltip: 'Play',
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.save, color: Color(0xFF4fc3f7)),
                          onPressed: () => _saveAsNew(appState),
                          tooltip: 'Save as new recording',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFe040fb)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PianoRoll(events: _expandedEvents),
                ),
              ],

              // Analysis
              if (_analysis != null) ...[
                const SizedBox(height: 24),
                const Text(
                  'Analysis',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _analysis!,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ],

              const Spacer(),

              // Analyze button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _analyze(appState),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Analyze Melody'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTypeName(ExpansionType type) {
    switch (type) {
      case ExpansionType.harmonize:
        return 'Harmonize';
      case ExpansionType.continue_:
        return 'Continue';
      case ExpansionType.variation:
        return 'Variation';
      case ExpansionType.accompaniment:
        return 'Accompaniment';
      case ExpansionType.fullSong:
        return 'Full Song';
    }
  }

  String _getTypeDescription(ExpansionType type) {
    switch (type) {
      case ExpansionType.harmonize:
        return 'Add chord tones and harmony to your melody';
      case ExpansionType.continue_:
        return 'Extend your melody in the same style';
      case ExpansionType.variation:
        return 'Create a variation with ornaments and modifications';
      case ExpansionType.accompaniment:
        return 'Generate a left-hand accompaniment pattern';
      case ExpansionType.fullSong:
        return 'Create a complete piano piece - fixes wrong notes, adds intro, development & ending';
    }
  }

  Future<void> _expand(AppState appState) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final events = await appState.aiService.expandMelody(
        widget.melody.events,
        _selectedType,
      );

      setState(() {
        _expandedEvents = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _analyze(AppState appState) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final analysis = await appState.aiService.analyzeMelody(
        widget.melody.events,
      );

      setState(() {
        _analysis = analysis;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _playExpanded() async {
    final appState = context.read<AppState>();

    if (!appState.synthService.isLoaded) {
      await appState.synthService.init();
    }

    // Stop any currently playing notes
    appState.synthService.stopAllNotes();

    if (_expandedEvents.isEmpty) return;

    // Normalize timestamps to start from 0
    final startOffset = _expandedEvents.first.timestamp;

    // Schedule all note events with timers
    for (final event in _expandedEvents) {
      final adjustedTime = event.timestamp - startOffset;
      Future.delayed(Duration(milliseconds: adjustedTime), () {
        if (event.isNoteOn) {
          appState.synthService.playNote(event.data1, event.data2);
        } else if (event.isNoteOff) {
          appState.synthService.stopNote(event.data1);
        }
      });
    }
  }

  Future<void> _saveAsNew(AppState appState) async {
    // Combine original and expanded events
    final combinedEvents = [
      ...widget.melody.events,
      ..._expandedEvents,
    ];

    final newMelody = Melody(
      title: '${widget.melody.title} (expanded)',
      createdAt: DateTime.now(),
      durationMs: combinedEvents.isNotEmpty ? combinedEvents.last.timestamp : 0,
      events: combinedEvents,
      notes: 'AI expanded from recording on ${widget.melody.createdAt}',
    );

    await appState.saveMelody(newMelody);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved as new recording')),
      );
      Navigator.pop(context);
    }
  }
}
