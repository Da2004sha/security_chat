import 'dart:math';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/session.dart';
import '../services/crypto_service.dart';
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

    if (priv == null || priv.isEmpty || pub == null || pub.isEmpty) {
      final (newPriv, newPub) =
          await CryptoService.instance.generateDeviceKeypair();
      priv = newPriv;
      pub = newPub;
    }

    final deviceName =
        Session.instance.deviceName ?? "device-${Random().nextInt(9999)}";

    final existingDevices =
        await Api.instance.getList("/users/$myUserId/devices");

    Map<String, dynamic>? sameDevice;
    for (final d in existingDevices.cast<Map<String, dynamic>>()) {
      if (d["pubkey_b64"] == pub) {
        sameDevice = d;
        break;
      }
    }

    if (sameDevice != null) {
      final existingId = sameDevice["id"] as int;

      await Session.instance.saveDevice(
        deviceId: existingId,
        deviceName: sameDevice["device_name"] as String? ?? deviceName,
        xPriv: priv,
        xPub: pub,
      );
      return;
    }

    final res = await Api.instance.post("/devices", {
      "device_name": deviceName,
      "pubkey_b64": pub,
    });

    final id = res["id"] as int;

    await Session.instance.saveDevice(
      deviceId: id,
      deviceName: deviceName,
      xPriv: priv,
      xPub: pub,
    );
  }

  Future<void> _submit() async {
    if (_busy) return;

    setState(() {
      _err = null;
      _busy = true;
    });

    try {
      final username = _u.text.trim();
      final password = _p.text;

      if (username.isEmpty || password.isEmpty) {
        throw Exception("Введите логин и пароль");
      }

      final path = _isLogin ? "/auth/login" : "/auth/register";

      final res = await Api.instance.post(
        path,
        {"username": username, "password": password},
        auth: false,
      );

      await Session.instance.saveAuth(
        token: res["access_token"],
        userId: res["user_id"],
      );

      await _ensureDeviceBoundToUser();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatsScreen()),
      );
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Secure Corp Chat")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _u,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            TextField(
              controller: _p,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            if (_err != null)
              Text(_err!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? "..." : (_isLogin ? "Login" : "Register")),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _isLogin = !_isLogin),
              child: Text(
                _isLogin ? "No account? Register" : "Have account? Login",
              ),
            ),
          ],
        ),
      ),
    );
  }
}