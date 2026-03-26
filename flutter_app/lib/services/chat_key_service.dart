import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'crypto_service.dart';
import 'session.dart';

class ChatKeyService {
  ChatKeyService._();
  static final ChatKeyService instance = ChatKeyService._();

  /// Импортирует chat keys, адресованные текущему устройству.
  ///
  /// ВАЖНО:
  /// Раньше здесь был skip, если локальный ключ уже существовал.
  /// Это ломало ситуацию после пересоздания чата / сброса БД, когда chatId
  /// совпадал, а локальный ключ оставался старый.
  ///
  /// Теперь ключ с сервера считается источником истины и перезаписывает локальный.
  Future<void> importMyChatKeys() async {
    final deviceId = Session.instance.deviceId;
    if (deviceId == null) return;

    final rows = await Api.instance.getList('/chat_keys/mine?device_id=$deviceId');

    for (final row in rows.cast<Map<String, dynamic>>()) {
      final chatId = row['chat_id'] as int;
      final wrappedByPub = row['wrapped_by_pubkey_b64'] as String;
      final wrappedJson = row['wrapped_key_json'] as String;

      try {
        final unwrapKey = await CryptoService.instance.deriveChatKey(
          myPrivB64: Session.instance.x25519PrivateKeyB64!,
          myPubB64: Session.instance.x25519PublicKeyB64!,
          theirPubB64: wrappedByPub,
          chatContext: 'chatkey:$chatId:device:${Session.instance.deviceId}',
        );

        final plain = await CryptoService.instance.decryptJson(
          payloadJson: wrappedJson,
          key: unwrapKey,
        );

        final chatKeyB64 = plain['chat_key_b64'] as String;
        final chatKey = Uint8List.fromList(base64Decode(chatKeyB64));

        // Всегда перезаписываем локальный ключ значением с сервера.
        await Session.instance.saveChatKey(chatId, chatKey);

        debugPrint('importMyChatKeys: chat key imported for chat=$chatId');
      } catch (e) {
        debugPrint('importMyChatKeys failed for chat=$chatId: $e');
      }
    }
  }

  Future<void> publishChatKeyForDevice({
    required int chatId,
    required Uint8List chatKey,
    required int targetDeviceId,
    required String targetPubB64,
  }) async {
    final wrapKey = await CryptoService.instance.deriveChatKey(
      myPrivB64: Session.instance.x25519PrivateKeyB64!,
      myPubB64: Session.instance.x25519PublicKeyB64!,
      theirPubB64: targetPubB64,
      chatContext: 'chatkey:$chatId:device:$targetDeviceId',
    );

    final wrappedJson = await CryptoService.instance.encryptJson(
      plaintext: {
        'chat_key_b64': base64Encode(chatKey),
      },
      key: wrapKey,
      aad: 'chatkey:$chatId:device:$targetDeviceId',
    );

    await Api.instance.post('/chat_keys', {
      'chat_id': chatId,
      'device_id': targetDeviceId,
      'wrapped_by_device_id': Session.instance.deviceId,
      'wrapped_key_json': wrappedJson,
    });
  }

  Future<void> publishChatKeyToAllParticipants({
    required int chatId,
    required Uint8List chatKey,
  }) async {
    final existingRows = await Api.instance.getList('/chat_keys/by_chat/$chatId');
    final existingDeviceIds = existingRows
        .cast<Map<String, dynamic>>()
        .map((e) => e['device_id'] as int)
        .toSet();

    final membersRaw = await Api.instance.getList('/chats/$chatId/members');
    final members = membersRaw.cast<Map<String, dynamic>>();

    for (final member in members) {
      final userId = member['id'] as int;
      final devices = await Api.instance.getList('/users/$userId/devices');

      for (final d in devices.cast<Map<String, dynamic>>()) {
        final targetDeviceId = d['id'] as int;
        final targetPub = d['pubkey_b64'] as String;

        if (existingDeviceIds.contains(targetDeviceId)) continue;

        try {
          await publishChatKeyForDevice(
            chatId: chatId,
            chatKey: chatKey,
            targetDeviceId: targetDeviceId,
            targetPubB64: targetPub,
          );
        } catch (e) {
          debugPrint(
            'publishChatKeyToAllParticipants failed for chat=$chatId device=$targetDeviceId: $e',
          );
        }
      }
    }
  }

  Future<void> syncChatKeyForChat(int chatId) async {
    final local = await Session.instance.getChatKey(chatId);

    if (local != null) {
      await publishChatKeyToAllParticipants(
        chatId: chatId,
        chatKey: local,
      );
    }

    // В любом случае импортируем с сервера ещё раз, чтобы получить
    // актуальный ключ, если локальный устарел.
    await importMyChatKeys();
  }

  Future<Uint8List?> ensureChatKey({
    required int chatId,
    int retries = 6,
    Duration delay = const Duration(milliseconds: 700),
  }) async {
    for (var i = 0; i < retries; i++) {
      await importMyChatKeys();

      final imported = await Session.instance.getChatKey(chatId);
      if (imported != null) {
        try {
          await publishChatKeyToAllParticipants(
            chatId: chatId,
            chatKey: imported,
          );
        } catch (e) {
          debugPrint('ensureChatKey publish failed for chat=$chatId: $e');
        }
        return imported;
      }

      if (i < retries - 1) {
        await Future.delayed(delay);
      }
    }

    return null;
  }

  Future<void> ensureChatKeyAvailable(int chatId) async {
    await ensureChatKey(chatId: chatId);
  }

  Future<Uint8List?> getChatKey(int chatId) async {
    return ensureChatKey(chatId: chatId, retries: 1, delay: Duration.zero);
  }

  Future<int> createChatAndDistributeKey({
    required List<String> memberUsernames,
    bool isGroup = false,
    String? title,
  }) async {
    final res = await Api.instance.post('/chats', {
      'member_usernames': memberUsernames,
      'is_group': isGroup,
      'title': title,
    });

    final chatId = res['id'] as int;

    final chatKey = CryptoService.instance.randomBytes(32);
    await Session.instance.saveChatKey(chatId, chatKey);

    await publishChatKeyToAllParticipants(
      chatId: chatId,
      chatKey: chatKey,
    );

    return chatId;
  }
}