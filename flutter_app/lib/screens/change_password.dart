import 'package:flutter/material.dart';
import '../services/api.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _repeat = TextEditingController();

  bool loading = false;
  String? error;
  String? success;

  Future<void> _submit() async {
    final current = _current.text.trim();
    final newPass = _new.text.trim();
    final repeat = _repeat.text.trim();

    if (newPass != repeat) {
      setState(() => error = 'Пароли не совпадают');
      return;
    }

    setState(() {
      loading = true;
      error = null;
      success = null;
    });

    try {
      await Api.instance.post('/auth/change-password', {
        'current_password': current,
        'new_password': newPass,
      });

      setState(() {
        success = 'Пароль успешно изменён';
      });

      _current.clear();
      _new.clear();
      _repeat.clear();
    } catch (e) {
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Смена пароля')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Текущий пароль'),
            ),
            TextField(
              controller: _new,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Новый пароль'),
            ),
            TextField(
              controller: _repeat,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Повторите пароль'),
            ),
            const SizedBox(height: 20),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            if (success != null)
              Text(success!, style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const CircularProgressIndicator()
                  : const Text('Сменить пароль'),
            ),
          ],
        ),
      ),
    );
  }
}