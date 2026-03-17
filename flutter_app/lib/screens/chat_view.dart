import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api.dart';
import '../services/chat_key_service.dart';
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
  Uint8List? _chatKey;

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

  Future<void> _ensureChatKey() async {
    _chatKey = await ChatKeyService.instance.getChatKey(widget.chatId);

    if (_chatKey != null) {
      await ChatKeyService.instance.publishChatKeyToAllParticipants(
        chatId: widget.chatId,
        chatKey: _chatKey!,
      );
      return;
    }

    await ChatKeyService.instance.importMyChatKeys();
    _chatKey = await ChatKeyService.instance.getChatKey(widget.chatId);

    if (_chatKey == null) {
      throw Exception("Нет ключа чата (multi-device ещё не синхронизировался)");
    }
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
      await _ensureChatKey();

      final res =
          await Api.instance.getList("/chats/${widget.chatId}/messages?limit=100");

      final out = <Map<String, dynamic>>[];

      for (final m in res.cast<Map<String, dynamic>>()) {
        try {
          final plain = await CryptoService.instance.decryptJson(
            payloadJson: m["payload_json"],
            key: _chatKey!,
          );

          out.add({
            "id": m["id"],
            "sender_user_id": m["sender_user_id"],
            "created_at": m["created_at"],
            ...plain,
          });
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        messages = out;
        loading = false;
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
      await _ensureChatKey();

      final payload = await CryptoService.instance.encryptJson(
        plaintext: {
          "type": "text",
          "text": text,
        },
        key: _chatKey!,
        aad: "chat:${widget.chatId}",
      );

      await Api.instance.post("/messages", {
        "chat_id": widget.chatId,
        "payload_json": payload,
        "sender_device_id": Session.instance.deviceId,
      });

      await _loadHistory(silent: true);
    } catch (e) {
      setState(() => err = e.toString());
    }
  }

  Future<void> _sendFile() async {
    try {
      await _ensureChatKey();

      final pick = await FilePicker.platform.pickFiles(withData: true);
      if (pick == null || pick.files.isEmpty) return;

      final file = pick.files.first;
      if (file.bytes == null) return;

      final fileKey = CryptoService.instance.randomBytes(32);
      final fileKeyB64 = base64Encode(fileKey);

      final encryptedFile = await CryptoService.instance.encryptBytes(
        plaintext: Uint8List.fromList(file.bytes!),
        key: fileKey,
        aad: "file:chat:${widget.chatId}",
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

      final payload = await CryptoService.instance.encryptJson(
        plaintext: {
          "type": "file",
          "attachment_id": att["attachment_id"],
          "name": file.name,
          "file_key_b64": fileKeyB64,
        },
        key: _chatKey!,
        aad: "chat:${widget.chatId}",
      );

      await Api.instance.post("/messages", {
        "chat_id": widget.chatId,
        "payload_json": payload,
        "sender_device_id": Session.instance.deviceId,
      });

      await _loadHistory(silent: true);
    } catch (e) {
      setState(() => err = e.toString());
    }
  }

  Future<void> _openFile(Map<String, dynamic> msg) async {
    try {
      final id = msg["attachment_id"];
      final fileKey = base64Decode(msg["file_key_b64"]);

      final response = await http.get(
        Api.instance.uri("/attachments/$id"),
        headers: Session.instance.authHeaders(),
      );

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
                    itemBuilder: (c, i) => ListTile(
                      title: Text(messages[i]["text"] ?? "[file]"),
                      onTap: messages[i]["type"] == "file"
                          ? () => _openFile(messages[i])
                          : null,
                    ),
                  ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: _sendFile,
              ),
              Expanded(
                child: TextField(
                  controller: _text,
                  decoration: const InputDecoration(hintText: "Message"),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendText,
              ),
            ],
          )
        ],
      ),
    );
  }
}