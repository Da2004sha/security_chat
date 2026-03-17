import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Session {
  Session._();
  static final Session instance = Session._();

  final _storage = const FlutterSecureStorage();

  String? token;
  int? userId;
  int? deviceId;

  String? deviceName;
  String? x25519PrivateKeyB64;
  String? x25519PublicKeyB64;

  static const _kToken = "token";
  static const _kUserId = "userId";
  static const _kDeviceId = "deviceId";
  static const _kDeviceName = "deviceName";
  static const _kXPriv = "xPriv";
  static const _kXPub = "xPub";

  static String _chatKeyStorageKey(int chatId) => "chatKey_$chatId";

  Future<void> init() async {
    token = await _storage.read(key: _kToken);

    final userIdStr = await _storage.read(key: _kUserId);
    userId = userIdStr == null ? null : int.tryParse(userIdStr);

    final deviceIdStr = await _storage.read(key: _kDeviceId);
    deviceId = deviceIdStr == null ? null : int.tryParse(deviceIdStr);

    deviceName = await _storage.read(key: _kDeviceName);
    x25519PrivateKeyB64 = await _storage.read(key: _kXPriv);
    x25519PublicKeyB64 = await _storage.read(key: _kXPub);
  }

  bool get isAuthed => token != null && userId != null;

  bool get hasDeviceKeys =>
      x25519PrivateKeyB64 != null &&
      x25519PrivateKeyB64!.isNotEmpty &&
      x25519PublicKeyB64 != null &&
      x25519PublicKeyB64!.isNotEmpty;

  Future<void> saveAuth({required String token, required int userId}) async {
    this.token = token;
    this.userId = userId;

    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kUserId, value: userId.toString());
  }

  Future<void> saveDevice({
    required int deviceId,
    required String deviceName,
    required String xPriv,
    required String xPub,
  }) async {
    this.deviceId = deviceId;
    this.deviceName = deviceName;
    x25519PrivateKeyB64 = xPriv;
    x25519PublicKeyB64 = xPub;

    await _storage.write(key: _kDeviceId, value: deviceId.toString());
    await _storage.write(key: _kDeviceName, value: deviceName);
    await _storage.write(key: _kXPriv, value: xPriv);
    await _storage.write(key: _kXPub, value: xPub);
  }

  Future<void> saveChatKey(int chatId, Uint8List key) async {
    await _storage.write(
      key: _chatKeyStorageKey(chatId),
      value: base64Encode(key),
    );
  }

  Future<Uint8List?> getChatKey(int chatId) async {
    final raw = await _storage.read(key: _chatKeyStorageKey(chatId));
    if (raw == null || raw.isEmpty) return null;
    return Uint8List.fromList(base64Decode(raw));
  }

  Future<void> deleteChatKey(int chatId) async {
    await _storage.delete(key: _chatKeyStorageKey(chatId));
  }

  Future<void> logout() async {
    token = null;
    userId = null;

    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUserId);
  }

  Future<void> wipeDevice() async {
    token = null;
    userId = null;
    deviceId = null;
    deviceName = null;
    x25519PrivateKeyB64 = null;
    x25519PublicKeyB64 = null;

    await _storage.deleteAll();
  }

  Map<String, String> authHeaders() {
    final t = token;
    if (t == null || t.isEmpty) return {};
    return {"Authorization": "Bearer $t"};
  }
}