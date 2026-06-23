import 'package:flutter/material.dart';

import 'core/database/local_database.dart';

/// Entry point for Orpheus.
///
/// The database is initialized before [runApp] so that every widget subtree
/// can safely access [LocalDatabase.instance] synchronously after startup.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
