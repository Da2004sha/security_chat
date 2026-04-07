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
  

  await Session.instance.init();
  runApp(const App());
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