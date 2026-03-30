import 'dart:math';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/chat_key_service.dart';
import '../services/crypto_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import 'chats.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _u = TextEditingController();
  final _p = TextEditingController();

  bool _isLogin = true;
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  Future<void> _ensureDeviceBoundToUser() async {
    final myUserId = Session.instance.userId!;

    String? priv = Session.instance.x25519PrivateKeyB64;
    String? pub = Session.instance.x25519PublicKeyB64;
    String? edPriv = Session.instance.ed25519PrivateKeyB64;
    String? edPub = Session.instance.ed25519PublicKeyB64;

    if (priv == null || priv.isEmpty || pub == null || pub.isEmpty) {
      final (newPriv, newPub) =
          await CryptoService.instance.generateDeviceKeypair();
      priv = newPriv;
      pub = newPub;
    }

    if (edPriv == null || edPriv.isEmpty || edPub == null || edPub.isEmpty) {
      final (newEdPriv, newEdPub) =
          await CryptoService.instance.generateSigningKeypair();
      edPriv = newEdPriv;
      edPub = newEdPub;
    }

    final deviceName =
        Session.instance.deviceName ?? 'device-${Random().nextInt(9999)}';

    final existingDevices = await Api.instance.getList('/users/$myUserId/devices');

    Map<String, dynamic>? sameDevice;
    for (final d in existingDevices.cast<Map<String, dynamic>>()) {
      if (d['pubkey_b64'] == pub) {
        sameDevice = d;
        break;
      }
    }

    if (sameDevice != null) {
      final existingId = sameDevice['id'] as int;

      await Session.instance.saveDevice(
        deviceId: existingId,
        deviceName: sameDevice['device_name'] as String? ?? deviceName,
        xPriv: priv,
        xPub: pub,
        edPriv: edPriv,
        edPub: edPub,
      );
      if ((sameDevice['sign_pubkey_b64']?.toString() ?? '') != edPub) {
        await Api.instance.post('/devices', {
          'device_name': sameDevice['device_name'] as String? ?? deviceName,
          'pubkey_b64': pub,
          'sign_pubkey_b64': edPub,
        });
      }
      return;
    }

    final res = await Api.instance.post('/devices', {
      'device_name': deviceName,
      'pubkey_b64': pub,
      'sign_pubkey_b64': edPub,
    });

    final id = res['id'] as int;

    await Session.instance.saveDevice(
      deviceId: id,
      deviceName: deviceName,
      xPriv: priv,
      xPub: pub,
      edPriv: edPriv,
      edPub: edPub,
    );
  }

  Future<void> _submit() async {
    if (_busy) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _err = null;
      _busy = true;
    });

    try {
      final username = _u.text.trim();
      final password = _p.text;

      if (username.isEmpty || password.isEmpty) {
        throw Exception('Введите логин и пароль');
      }

      final path = _isLogin ? '/auth/login' : '/auth/register';

      final res = await Api.instance.post(
        path,
        {'username': username, 'password': password},
        auth: false,
      );

      await Session.instance.saveAuth(
        token: res['access_token'],
        userId: res['user_id'],
      );

      await _ensureDeviceBoundToUser();
      await ChatKeyService.instance.importMyChatKeys();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatsScreen()),
      );
    } catch (e) {
      setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isLogin ? 'Вход' : 'Регистрация';
    final buttonText = _isLogin ? 'Войти' : 'Зарегистрироваться';
    final switchLead = _isLogin ? 'Нет аккаунта?' : 'Уже есть аккаунт?';
    final switchAction = _isLogin ? 'Зарегистрироваться' : 'Войти';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7FAFD), Color(0xFFEFF4FA)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_rounded,
                            size: 34,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Защищённый чат',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Безопасный обмен сообщениями и файлами в корпоративной сети.',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _u,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Логин',
                            hintText: 'Введите логин',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _p,
                          obscureText: true,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Пароль',
                            hintText: 'Введите пароль',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                        if (_err != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEECEC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFF7C9C9)),
                            ),
                            child: Text(
                              _err!,
                              style: const TextStyle(
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(_busy ? 'Подождите...' : buttonText),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              switchLead,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _isLogin = !_isLogin),
                              child: Text(switchAction),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
