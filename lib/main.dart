import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_shell.dart';
import 'core/settings.dart';
import 'core/sphere_repository.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: AppTheme.bg,
  ));

  final prefs = await SharedPreferences.getInstance();
  final repository = await SphereRepository.create();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsController(prefs)),
      Provider<SphereRepository>.value(value: repository),
    ],
    child: const Sphere360App(),
  ));
}

class Sphere360App extends StatelessWidget {
  const Sphere360App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '360Sphere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}
