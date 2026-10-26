import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_controller.dart';

export 'app.dart' show GradePulseApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final controller = AppController(prefs)..init();
  runApp(GradePulseApp(controller: controller));
}
