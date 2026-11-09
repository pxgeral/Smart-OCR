import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // Nilai disimpan sebagai string JSON -> tanpa codegen / TypeAdapter.
  await Future.wait([
    Hive.openBox<String>(AppConstants.projectsBox),
    Hive.openBox<String>(AppConstants.ocrCacheBox),
  ]);
  runApp(const ProviderScope(child: App()));
}
