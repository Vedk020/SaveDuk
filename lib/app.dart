import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/constants.dart';
import 'screens/home_screen.dart';
import 'screens/music_screen.dart';
import 'screens/library_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/mini_player.dart';

/// Root app widget with bottom navigation
class SaveDukApp extends StatelessWidget {
  const SaveDukApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaveDuk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppShell(),
    );
  }
}

/// App shell with bottom navigation
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    MusicScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Persistent Mini Audio Player across all screens with paint boundary
          RepaintBoundary(child: const MiniPlayer()),

          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                if (index != _currentIndex) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentIndex = index);
                }
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.download_rounded),
                  activeIcon: Icon(Icons.download_rounded),
                  label: 'GET',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.music_note_outlined),
                  activeIcon: Icon(Icons.music_note_rounded),
                  label: 'MUSIC',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.video_library_outlined),
                  activeIcon: Icon(Icons.video_library_rounded),
                  label: 'SAVED',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
