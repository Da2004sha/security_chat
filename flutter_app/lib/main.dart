import 'dart:io';

import 'package:flutter/material.dart';

import 'screens/chats.dart';
import 'screens/login.dart';
import 'services/session.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Для тестов через ngrok на Android/Windows.
  // Это ослабляет проверку сертификатов, поэтому для продакшена так не оставляют.
  HttpOverrides.global = _DevHttpOverrides();

  await Session.instance.init();
  runApp(const App());
}

class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Защищённый чат',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Session.instance.isAuthed
          ? const ChatsScreen()
          : const LoginScreen(),
    );
  }
}