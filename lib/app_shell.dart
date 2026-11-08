import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'gallery/my360s_screen.dart';
import 'settings/settings_screen.dart';

/// Root shell: bottom navigation (My 360s / Settings), like the original
/// app's main tabs minus the cloud/community tabs that need a backend.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          My360sScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.accent.withValues(alpha: 0.25),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.panorama_photosphere_outlined),
            selectedIcon: Icon(Icons.panorama_photosphere),
            label: 'My 360s',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
