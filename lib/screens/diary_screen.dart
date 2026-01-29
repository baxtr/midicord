import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/melody.dart';
import '../widgets/practice_calendar.dart';
import 'session_screen.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  DateTime? _selectedDate;
  List<Melody> _selectedDayMelodies = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMelodiesForDate(_selectedDate!);
    });
  }

  Future<void> _loadMelodiesForDate(DateTime date) async {
    if (!mounted) return;
    try {
      final appState = context.read<AppState>();
      final melodies = await appState.getMelodiesForDate(date);
      if (mounted) {
        setState(() {
          _selectedDayMelodies = melodies;
        });
      }
    } catch (e) {
      print('Error loading melodies: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF0f0f1a),
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Practice Diary',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${appState.melodies.length} recordings',
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                        const SizedBox(height: 24),

                        // Practice calendar
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a1a2e),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: PracticeCalendar(
                            practiceByDay: appState.practiceByDay,
                            selectedDate: _selectedDate,
                            onDaySelected: (date) {
                              setState(() => _selectedDate = date);
                              _loadMelodiesForDate(date);
                            },
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Selected day header
                        if (_selectedDate != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat('EEEE, MMMM d').format(_selectedDate!),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_selectedDayMelodies.isNotEmpty)
                                Text(
                                  '${_selectedDayMelodies.length} sessions',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),

                // Melodies list
                if (_selectedDayMelodies.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_off,
                            color: Colors.white24,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No recordings this day',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final melody = _selectedDayMelodies[index];
                          return _buildMelodyCard(melody, appState);
                        },
                        childCount: _selectedDayMelodies.length,
                      ),
                    ),
                  ),

                // Bottom padding
                const SliverToBoxAdapter(
                  child: SizedBox(height: 20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMelodyCard(Melody melody, AppState appState) {
    final time = DateFormat('h:mm a').format(melody.createdAt);
    final noteCount = melody.events.where((e) => e.isNoteOn).length;

    return Card(
      color: const Color(0xFF1a1a2e),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SessionScreen(melody: melody),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Time indicator
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF4fc3f7).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.music_note,
                  color: Color(0xFF4fc3f7),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$noteCount notes \u2022 ${melody.durationFormatted}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                    if (melody.notes != null && melody.notes!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        melody.notes!,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Arrow
              const Icon(
                Icons.chevron_right,
                color: Colors.white24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
