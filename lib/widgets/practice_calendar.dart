import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PracticeCalendar extends StatefulWidget {
  final Map<DateTime, int> practiceByDay;
  final Function(DateTime) onDaySelected;
  final DateTime? selectedDate;

  const PracticeCalendar({
    super.key,
    required this.practiceByDay,
    required this.onDaySelected,
    this.selectedDate,
  });

  @override
  State<PracticeCalendar> createState() => _PracticeCalendarState();
}

class _PracticeCalendarState extends State<PracticeCalendar> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(
      widget.selectedDate?.year ?? DateTime.now().year,
      widget.selectedDate?.month ?? DateTime.now().month,
    );
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    if (nextMonth.isBefore(DateTime(now.year, now.month + 1))) {
      setState(() {
        _currentMonth = nextMonth;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Month navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: _previousMonth,
            ),
            Text(
              DateFormat('MMMM yyyy').format(_currentMonth),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.chevron_right,
                color: _canGoNext() ? Colors.white : Colors.white24,
              ),
              onPressed: _canGoNext() ? _nextMonth : null,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Weekday headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
              .map((d) => SizedBox(
                    width: 40,
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),

        // Calendar grid
        _buildCalendarGrid(),

        const SizedBox(height: 12),

        // Legend
        _buildLegend(),
      ],
    );
  }

  bool _canGoNext() {
    final now = DateTime.now();
    final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    return nextMonth.isBefore(DateTime(now.year, now.month + 1));
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0
    final daysInMonth = lastDayOfMonth.day;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final rows = <Widget>[];
    var dayCounter = 1 - firstWeekday;

    while (dayCounter <= daysInMonth) {
      final cells = <Widget>[];

      for (var i = 0; i < 7; i++) {
        if (dayCounter < 1 || dayCounter > daysInMonth) {
          // Empty cell
          cells.add(const SizedBox(width: 40, height: 40));
        } else {
          final date = DateTime(_currentMonth.year, _currentMonth.month, dayCounter);
          final dayKey = DateTime(date.year, date.month, date.day);
          final practiceMs = widget.practiceByDay[dayKey] ?? 0;
          final isSelected = widget.selectedDate != null &&
              dayKey.year == widget.selectedDate!.year &&
              dayKey.month == widget.selectedDate!.month &&
              dayKey.day == widget.selectedDate!.day;
          final isToday = dayKey == today;
          final isFuture = dayKey.isAfter(today);

          cells.add(
            GestureDetector(
              onTap: isFuture ? null : () => widget.onDaySelected(dayKey),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isFuture
                      ? Colors.transparent
                      : _getColorForPractice(practiceMs),
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: const Color(0xFF4fc3f7), width: 2)
                      : isToday
                          ? Border.all(color: Colors.white54, width: 1)
                          : null,
                ),
                child: Center(
                  child: Text(
                    dayCounter.toString(),
                    style: TextStyle(
                      color: isFuture ? Colors.white24 : Colors.white,
                      fontSize: 14,
                      fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        dayCounter++;
      }

      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: cells,
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Less', style: TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(width: 6),
        ...List.generate(5, (i) => Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: _getLegendColor(i),
            borderRadius: BorderRadius.circular(4),
          ),
        )),
        const SizedBox(width: 6),
        const Text('More', style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Color _getColorForPractice(int ms) {
    if (ms == 0) return const Color(0xFF252538);
    if (ms < 15 * 60 * 1000) return const Color(0xFF0e4429); // < 15 min
    if (ms < 45 * 60 * 1000) return const Color(0xFF006d32); // < 45 min
    if (ms < 90 * 60 * 1000) return const Color(0xFF26a641); // < 90 min
    return const Color(0xFF39d353); // 90+ min
  }

  Color _getLegendColor(int level) {
    switch (level) {
      case 0: return const Color(0xFF252538);
      case 1: return const Color(0xFF0e4429);
      case 2: return const Color(0xFF006d32);
      case 3: return const Color(0xFF26a641);
      case 4: return const Color(0xFF39d353);
      default: return const Color(0xFF252538);
    }
  }
}
