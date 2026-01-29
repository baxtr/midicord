import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/home_screen.dart';
import 'screens/diary_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations - allow all
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0f0f1a),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Add error handling
  FlutterError.onError = (details) {
    print('Flutter Error: ${details.exception}');
    print('Stack: ${details.stack}');
  };

  runApp(const MidicordApp());
}

class MidicordApp extends StatelessWidget {
  const MidicordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Midicord',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF4fc3f7),
          scaffoldBackgroundColor: const Color(0xFF0f0f1a),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4fc3f7),
            secondary: Color(0xFFe040fb),
            surface: Color(0xFF1a1a2e),
          ),
          useMaterial3: true,
        ),
        home: const MainNavigation(),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      body: _currentIndex == 0
          ? const HomeScreen()
          : const DiaryScreen(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF1a1a2e),
        selectedItemColor: const Color(0xFF4fc3f7),
        unselectedItemColor: Colors.white38,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.radio_button_checked),
            label: 'Record',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: 'Diary',
          ),
        ],
      ),
    );
  }
}
