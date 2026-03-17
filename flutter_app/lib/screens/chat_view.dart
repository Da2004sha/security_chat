import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api.dart';
import '../services/crypto_service.dart';
import '../services/session.dart';
import '../widgets/message_tile.dart';

class ChatViewScreen extends StatefulWidget {
  final int chatId;
  final String title;

  const ChatViewScreen({
    super.key,
    required this.chatId,
    required this.title,
  });

  @override
  State<ChatViewScreen> createState() => _ChatViewScreenState();
}

class _ChatViewScreenState extends State<ChatViewScreen> {
  final _text = TextEditingController();

  bool loading = true;
  bool _refreshing = false;
  String? err;

  List<Map<String, dynamic>> messages = [];

  Map<int, Uint8List> _participantDeviceKeys = {};
  Map<int, String> _devicePubkeys = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadHistory();

    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadHistory(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    final out = Uint8List(n);
    for (int i = 0; i < n; i++) {
      out[i] = r.nextInt(256);
    }
    return out;
  }

  Future<void> _deriveParticipantDeviceKeys() async {
    final membersRaw =
        await Api.instance.getList("/chats/${widget.chatId}/members");

    final members = membersRaw.cast<Map<String, dynamic>>();
    final result = <int, Uint8List>{};
    final pubkeys = <int, String>{};

    for (final member in members) {
      final userId = member["id"] as int;
      final devices = await Api.instance.getList("/users/$userId/devices");

      for (final d in devices.cast<Map<String, dynamic>>()) {
        final deviceId = d["id"] as int;
        final pub = d["pubkey_b64"] as String;

        pubkeys[deviceId] = pub;

        final key = await CryptoService.instance.deriveChatKey(
          myPrivB64: Session.instance.x25519PrivateKeyB64!,
          myPubB64: Session.instance.x25519PublicKeyB64!,
          theirPubB64: pub,
          chatContext: "chat:${widget.chatId}:device:$deviceId",
        );

        result[deviceId] = key;
      }
    }

    if (result.isEmpty) {
      throw Exception("Не найдено ни одного устройства участников чата");
    }

    _participantDeviceKeys = result;
    _devicePubkeys = pubkeys;
  }

  String? _extractPayloadForCurrentDevice(dynamic raw) {
    final myDeviceId = Session.instance.deviceId?.toString();
    if (myDeviceId == null) return null;

    if (raw is String) {
      final trimmed = raw.trim();

      if (trimmed.startsWith('{') && trimmed.contains('"multi_device"')) {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic> &&
            decoded["multi_device"] == true) {
          final payloadsRaw = decoded["payloads"];
          if (payloadsRaw is Map) {
            final payloads = Map<String, dynamic>.from(payloadsRaw);
            final picked = payloads[myDeviceId];
            return picked is String ? picked : null;
          }
        }
        return null;
      }

      return trimmed;
    }

    if (raw is Map) {
      final decoded = Map<String, dynamic>.from(raw);
      if (decoded["multi_device"] == true) {
        final payloadsRaw = decoded["payloads"];
        if (payloadsRaw is Map) {
          final payloads = Map<String, dynamic>.from(payloadsRaw);
          final picked = payloads[myDeviceId];
          return picked is String ? picked : null;
        }
      }
      return null;
    }

    return null;
  }

  Future<Uint8List?> _deriveReadKeyForMessage(Map<String, dynamic> m) async {
    final senderDeviceId = m["sender_device_id"] as int?;
    if (senderDeviceId == null) return null;

    final senderPub = _devicePubkeys[senderDeviceId];
    if (senderPub == null) return null;

    return CryptoService.instance.deriveChatKey(
      myPrivB64: Session.instance.x25519PrivateKeyB64!,
      myPubB64: Session.instance.x25519PublicKeyB64!,
      theirPubB64: senderPub,
      chatContext: "chat:${widget.chatId}:device:${Session.instance.deviceId}",
    );
  }

  Future<void> _loadHistory({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;

    if (!silent) {
      setState(() {
        loading = true;
        err = null;
      });
    }

    try {
      await _deriveParticipantDeviceKeys();

      final res =
          await Api.instance.getList("/chats/${widget.chatId}/messages?limit=100");

      final out = <Map<String, dynamic>>[];

      for (final m in res.cast<Map<String, dynamic>>()) {
        final payloadForMe = _extractPayloadForCurrentDevice(m["payload_json"]);
        if (payloadForMe == null) {
          continue;
        }

        final keyForMessage = await _deriveReadKeyForMessage(m);
        if (keyForMessage == null) {
          continue;
        }

        try {
          final plain = await CryptoService.instance.decryptJson(
            payloadJson: payloadForMe,
            key: keyForMessage,
          );

          out.add({
            "id": m["id"],
            "sender_user_id": m["sender_user_id"],
            "sender_device_id": m["sender_device_id"],
            "created_at": m["created_at"],
            ...plain,
          });
        } catch (_) {
          continue;
        }
      }

      if (!mounted) return;
      setState(() {
        messages = out;
        loading = false;
        if (!silent) err = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        err = e.toString();
        loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;

    _text.clear();

    try {
      await _deriveParticipantDeviceKeys();

      if (_participantDeviceKeys.isEmpty) {
        throw Exception("Нет устройств участников чата");
      }

      final payloads = <Map<String, dynamic>>[];

      for (final entry in _participantDeviceKeys.entries) {
        final recipientDeviceId = entry.key;
        final key = entry.value;

        final payload = await CryptoService.instance.encryptJson(
          plaintext: {
            "type": "text",
            "text": text,
          },
          key: key,
          aad: "chat:${widget.chatId}:device:$recipientDeviceId",
        );

        payloads.add({
          "recipient_device_id": recipientDeviceId,
          "payload_json": payload,
        });
      }

      await Api.instance.post("/messages", {
        "chat_id": widget.chatId,
        "sender_device_id": Session.instance.deviceId,
        "payloads": payloads,
      });

      await _loadHistory(silent: true);
    } catch (e) {
      setState(() => err = e.toString());
    }
  }

  Future<void> _sendFile() async {
    try {
      await _deriveParticipantDeviceKeys();

      if (_participantDeviceKeys.isEmpty) {
        throw Exception("Нет устройств участников чата");
      }

      final pick = await FilePicker.platform.pickFiles(withData: true);
      if (pick == null || pick.files.isEmpty) return;

      final file = pick.files.first;
      if (file.bytes == null) return;

      final fileKey = _randomBytes(32);
      final fileKeyB64 = base64Encode(fileKey);

      final encryptedFile = await CryptoService.instance.encryptBytes(
        plaintext: Uint8List.fromList(file.bytes!),
        key: fileKey,
        aad: "file:chat:${widget.chatId}:attachment",
      );

      final req =
          http.MultipartRequest("POST", Api.instance.uri("/attachments"));
      req.headers.addAll(Session.instance.authHeaders());

      req.files.add(
        http.MultipartFile.fromBytes(
          "file",
          encryptedFile,
          filename: "${file.name}.e2ee",
        ),
      );

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode >= 400) {
        throw Exception(body);
      }

      final att = jsonDecode(body);

      final payloads = <Map<String, dynamic>>[];

      for (final entry in _participantDeviceKeys.entries) {
        final recipientDeviceId = entry.key;
        final key = entry.value;

        final payload = await CryptoService.instance.encryptJson(
          plaintext: {
            "type": "file",
            "attachment_id": att["attachment_id"],
            "name": file.name,
            "file_key_b64": fileKeyB64,
          },
          key: key,
          aad: "chat:${widget.chatId}:device:$recipientDeviceId",
        );

        payloads.add({
          "recipient_device_id": recipientDeviceId,
          "payload_json": payload,
        });
      }

      await Api.instance.post("/messages", {
        "chat_id": widget.chatId,
        "sender_device_id": Session.instance.deviceId,
        "payloads": payloads,
      });

      await _loadHistory(silent: true);
    } catch (e) {
      setState(() => err = e.toString());
    }
  }

  Future<void> _openFile(Map<String, dynamic> msg) async {
    try {
      final id = msg["attachment_id"];
      if (id == null) throw Exception("Нет attachment_id");

      final fileKeyB64 = msg["file_key_b64"];
      if (fileKeyB64 == null || fileKeyB64 is! String || fileKeyB64.isEmpty) {
        throw Exception("Нет file_key_b64");
      }

      final fileKey = base64Decode(fileKeyB64);

      final response = await http.get(
        Api.instance.uri("/attachments/$id"),
        headers: Session.instance.authHeaders(),
      );

      if (response.statusCode >= 400) {
        throw Exception("Ошибка скачивания");
      }

      final plain = await CryptoService.instance.decryptBytes(
        packedJsonBytes: response.bodyBytes,
        key: Uint8List.fromList(fileKey),
      );

      final dir = await getTemporaryDirectory();
      final path = "${dir.path}/${msg["name"]}";
      final file = File(path);
      await file.writeAsBytes(plain);

      await OpenFilex.open(path);
    } catch (e) {
      setState(() => err = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          if (err != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(err!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (c, i) => MessageTile(
                      message: messages[i],
                      onOpenFile: _openFile,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _sendFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: const InputDecoration(hintText: "Message"),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}