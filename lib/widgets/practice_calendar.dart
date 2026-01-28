import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PracticeCalendar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = (constraints.maxWidth - 40) / 53; // 52 weeks + padding
        final now = DateTime.now();
        final startDate = DateTime(now.year - 1, now.month, now.day);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month labels
            _buildMonthLabels(startDate, cellSize),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Day labels
                _buildDayLabels(cellSize),
                const SizedBox(width: 4),
                // Calendar grid
                Expanded(
                  child: _buildGrid(startDate, cellSize),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Legend
            _buildLegend(),
          ],
        );
      },
    );
  }

  Widget _buildMonthLabels(DateTime startDate, double cellSize) {
    final months = <Widget>[];
    var currentMonth = -1;
    var weekCount = 0;

    for (var date = startDate;
        date.isBefore(DateTime.now().add(const Duration(days: 1)));
        date = date.add(const Duration(days: 7))) {
      if (date.month != currentMonth) {
        if (currentMonth != -1) {
          months.add(SizedBox(width: weekCount * cellSize));
        }
        months.add(Text(
          DateFormat('MMM').format(date),
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ));
        currentMonth = date.month;
        weekCount = 0;
      }
      weekCount++;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 28),
      child: Row(children: months),
    );
  }

  Widget _buildDayLabels(double cellSize) {
    const days = ['', 'Mon', '', 'Wed', '', 'Fri', ''];
    return Column(
      children: days.map((d) => SizedBox(
        height: cellSize,
        child: Text(
          d,
          style: const TextStyle(fontSize: 9, color: Colors.grey),
        ),
      )).toList(),
    );
  }

  Widget _buildGrid(DateTime startDate, double cellSize) {
    final weeks = <Widget>[];
    var currentDate = startDate;

    // Adjust to start on Sunday
    while (currentDate.weekday != DateTime.sunday) {
      currentDate = currentDate.subtract(const Duration(days: 1));
    }

    final now = DateTime.now();

    while (currentDate.isBefore(now.add(const Duration(days: 1)))) {
      final days = <Widget>[];

      for (var i = 0; i < 7; i++) {
        final date = currentDate.add(Duration(days: i));
        final dayKey = DateTime(date.year, date.month, date.day);
        final practiceMs = practiceByDay[dayKey] ?? 0;
        final isSelected = selectedDate != null &&
            dayKey.year == selectedDate!.year &&
            dayKey.month == selectedDate!.month &&
            dayKey.day == selectedDate!.day;

        days.add(
          GestureDetector(
            onTap: () => onDaySelected(dayKey),
            child: Container(
              width: cellSize - 2,
              height: cellSize - 2,
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: _getColorForPractice(practiceMs),
                borderRadius: BorderRadius.circular(2),
                border: isSelected
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
            ),
          ),
        );
      }

      weeks.add(Column(children: days));
      currentDate = currentDate.add(const Duration(days: 7));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true, // Show recent dates first
      child: Row(children: weeks),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text('Less', style: TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(width: 4),
        ...List.generate(5, (i) => Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: _getLegendColor(i),
            borderRadius: BorderRadius.circular(2),
          ),
        )),
        const SizedBox(width: 4),
        const Text('More', style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Color _getColorForPractice(int ms) {
    if (ms == 0) return const Color(0xFF1a1a2e);
    if (ms < 15 * 60 * 1000) return const Color(0xFF0e4429); // < 15 min
    if (ms < 45 * 60 * 1000) return const Color(0xFF006d32); // < 45 min
    if (ms < 90 * 60 * 1000) return const Color(0xFF26a641); // < 90 min
    return const Color(0xFF39d353); // 90+ min
  }

  Color _getLegendColor(int level) {
    switch (level) {
      case 0: return const Color(0xFF1a1a2e);
      case 1: return const Color(0xFF0e4429);
      case 2: return const Color(0xFF006d32);
      case 3: return const Color(0xFF26a641);
      case 4: return const Color(0xFF39d353);
      default: return const Color(0xFF1a1a2e);
    }
  }
}
