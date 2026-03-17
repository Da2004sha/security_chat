import 'package:flutter/material.dart';
import 'screens/chats.dart';
import 'screens/login.dart';
import 'services/session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Corp Chat',
      theme: ThemeData(useMaterial3: true),
      home: Session.instance.isAuthed
          ? const ChatsScreen()
          : const LoginScreen(),
    );
  }
}