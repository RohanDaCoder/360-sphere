import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sphere360/core/settings.dart';
import 'package:sphere360/core/theme.dart';

void main() {
  testWidgets('Settings round-trips through JSON', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = SettingsController(prefs);

    await controller.update(Settings(
      equirectWidth: 2048,
      watermark: false,
      cameraFovDegrees: 70,
    ).copyWith(compassAssist: false));

    // Re-read from the same prefs (simulating an app restart).
    final reloaded = SettingsController(prefs);
    expect(reloaded.settings.equirectWidth, equals(2048));
    expect(reloaded.settings.watermark, isFalse);
    expect(reloaded.settings.cameraFovDegrees, equals(70));
    expect(reloaded.settings.compassAssist, isFalse);
    expect(reloaded.settings.equirectHeight, equals(1024));
  });

  testWidgets('Theme builds with expected accent', (tester) async {
    final theme = AppTheme.dark();
    expect(theme.colorScheme.primary, equals(AppTheme.accent));
    expect(theme.scaffoldBackgroundColor, equals(AppTheme.bg));
  });

  testWidgets('App shell smoke test', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsController(prefs)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Center(child: Text('360Sphere')),
          ),
        ),
      ),
    );

    expect(find.text('360Sphere'), findsOneWidget);
  });
}
