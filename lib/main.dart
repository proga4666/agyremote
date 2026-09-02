import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/network/bridge_client.dart';
import 'core/theme/app_theme.dart';
import 'providers/chat_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/project_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final bridge = BridgeClient();
  bridge.connect('ws://192.168.0.109:7800/ws');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ConnectionProvider(bridge: bridge),
        ),
        ChangeNotifierProvider(
          create: (_) => ProjectProvider(bridge: bridge)..fetchProjects(),
        ),
        ChangeNotifierProvider(create: (_) => ChatProvider(bridge: bridge)),
      ],
      child: const AntigravityRemoteApp(),
    ),
  );
}

class AntigravityRemoteApp extends StatelessWidget {
  const AntigravityRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Antigravity Remote',
      debugShowCheckedModeBanner: false,
      theme: AntigravityTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
