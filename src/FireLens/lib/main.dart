import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/firebase_provider.dart';
import 'screens/connection_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => FirebaseProvider(),
      child: const FireLensApp(),
    ),
  );
}

class FireLensApp extends StatelessWidget {
  const FireLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FireLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const _AppRoot(),
    );
  }
}

/// Handles the initial "auto-reconnect from saved credentials" flow.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    await context.read<FirebaseProvider>().loadSavedConfig();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final isConnected = context.watch<FirebaseProvider>().isConnected;
    return isConnected ? const DashboardScreen() : const ConnectionScreen();
  }
}
