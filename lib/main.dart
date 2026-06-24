import 'package:flutter/material.dart';
import 'package:metadata_god/metadata_god.dart';

import 'core/database/local_database.dart';

/// Entry point for Orpheus.
///
/// Initialization order is important:
/// 1. [WidgetsFlutterBinding.ensureInitialized] — required by platform plugins.
/// 2. [MetadataGod.initialize] — loads the Rust FFI bridge for tag reading.
/// 3. [LocalDatabase.instance.initialize] — opens Isar and seeds default data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MetadataGod.initialize();
  await LocalDatabase.instance.initialize();

  runApp(const OrpheusApp());
}

/// Root widget — intentionally minimal until the UI layer is built.
class OrpheusApp extends StatelessWidget {
  const OrpheusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: Center(
          child: Text(
            'Orpheus — Data Layer initialized ✓',
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}
