import 'package:flutter/material.dart';
import 'config/constants.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'theme/app_theme.dart';

/// Root app widget with bottom navigation
class SaveDukApp extends StatelessWidget {
  final String? initialSharedUrl;

  const SaveDukApp({super.key, this.initialSharedUrl});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaveDuk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: AppShell(initialSharedUrl: initialSharedUrl),
    );
  }
}

/// App shell with bottom navigation
class AppShell extends StatefulWidget {
  final String? initialSharedUrl;

  const AppShell({super.key, this.initialSharedUrl});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(key: _homeKey, sharedUrl: widget.initialSharedUrl),
      const LibraryScreen(),
    ];
  }

  /// Called from main.dart when a new URL is shared
  void handleSharedUrl(String url) {
    setState(() {
      _currentIndex = 0; // switch to home tab
    });
    _homeKey.currentState?.handleSharedUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.download_rounded),
              activeIcon: Icon(Icons.download_rounded),
              label: 'GET',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.video_library_outlined),
              activeIcon: Icon(Icons.video_library_rounded),
              label: 'SAVED',
            ),
          ],
        ),
      ),
    );
  }
}
