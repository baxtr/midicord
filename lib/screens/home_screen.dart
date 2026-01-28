import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import '../providers/app_state.dart';
import '../widgets/live_midi_display.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MidiDevice> _devices = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanDevices();
    });
  }

  Future<void> _scanDevices() async {
    if (!mounted) return;
    setState(() => _scanning = true);
    try {
      final appState = context.read<AppState>();
      final devices = await appState.midiService.getDevices();
      if (mounted) {
        setState(() {
          // Filter out network sessions - only show real MIDI devices
          _devices = devices.where((d) => !d.name.contains('Network Session')).toList();
          _scanning = false;
        });
      }
    } catch (e) {
      print('Error scanning devices: $e');
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF0f0f1a),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Midicord',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white54),
                        onPressed: () => _showSettings(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildConnectionCard(appState),
                  const Spacer(),
                  _buildQuickStats(appState),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionCard(AppState appState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: appState.isConnected
              ? const Color(0xFF26a641)
              : Colors.white10,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                appState.isConnected ? Icons.piano : Icons.piano_off,
                color: appState.isConnected
                    ? const Color(0xFF26a641)
                    : Colors.white54,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appState.isConnected ? 'Connected' : 'No Device',
                      style: TextStyle(
                        color: appState.isConnected
                            ? const Color(0xFF26a641)
                            : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (appState.midiService.connectedDevice != null)
                      Text(
                        appState.midiService.connectedDevice!.name,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              if (_scanning)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white54),
                  onPressed: _scanDevices,
                ),
            ],
          ),
          if (!appState.isConnected && _devices.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),
            ..._devices.map((device) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.usb, color: Colors.white54),
                  title: Text(
                    device.name,
                    style: const TextStyle(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: SizedBox(
                    width: 80,
                    child: TextButton(
                      onPressed: () async {
                        print('Connecting to: ${device.name} (${device.id})');
                        await appState.midiService.connect(device);
                        setState(() {});
                      },
                      child: const Text('Connect'),
                    ),
                  ),
                )),
          ],
          if (!appState.isConnected && _devices.isEmpty && !_scanning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Connect your MIDI device via USB',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingCard(AppState appState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: appState.isRecording
            ? const Color(0xFF2e1a1a)
            : const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: appState.isRecording ? Colors.red : Colors.white10,
          width: appState.isRecording ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: appState.isRecording ? Colors.red : Colors.white24,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appState.isRecording ? 'Recording...' : 'Ready',
                  style: TextStyle(
                    color: appState.isRecording ? Colors.red : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  appState.isRecording
                      ? 'Play to continue, pause to save'
                      : 'Start playing to record automatically',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          ),
          if (appState.isRecording)
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.red, size: 32),
              onPressed: () async {
                final melody = appState.stopRecording();
                if (melody != null) {
                  await appState.saveMelody(melody);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Recording saved!')),
                    );
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(AppState appState) {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final todayPractice = appState.practiceByDay[todayKey] ?? 0;
    final todayMinutes = todayPractice ~/ 60000;

    final totalRecordings = appState.melodies.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('Today', '${todayMinutes}m'),
          _buildStat('Recordings', '$totalRecordings'),
          _buildStat('Streak', '${_calculateStreak(appState)}d'),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  int _calculateStreak(AppState appState) {
    int streak = 0;
    var date = DateTime.now();
    int daysChecked = 0;
    const maxDaysToCheck = 365;

    while (daysChecked < maxDaysToCheck) {
      final dayKey = DateTime(date.year, date.month, date.day);
      if (appState.practiceByDay.containsKey(dayKey)) {
        streak++;
        date = date.subtract(const Duration(days: 1));
      } else if (streak == 0 && daysChecked < 1) {
        // Only skip one day if we haven't played today yet
        date = date.subtract(const Duration(days: 1));
      } else {
        break;
      }
      daysChecked++;
    }

    return streak;
  }

  void _showSettings(BuildContext context) {
    final appState = context.read<AppState>();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.key, color: Colors.white54),
              title: const Text(
                'OpenRouter API Key',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Required for AI features',
                style: TextStyle(color: Colors.white38),
              ),
              onTap: () => _showApiKeyDialog(context, appState),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white54),
              title: const Text(
                'About Midicord',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Version 1.0.0',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showApiKeyDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('API Key', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter your OpenRouter API key',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              appState.setApiKey(controller.text);
              Navigator.pop(context);
              Navigator.pop(context); // Close settings too
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('API key saved')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
