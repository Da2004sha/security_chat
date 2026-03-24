import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api.dart';
import '../services/chat_key_service.dart';
import '../services/crypto_service.dart';
import '../services/session.dart';
import '../services/voice_recorder_service.dart';
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
  bool recording = false;
  String? err;

  List<Map<String, dynamic>> messages = [];
  Uint8List? _chatKey;

  Timer? _timer;

  bool get _canRecordVoice => VoiceRecorderService.instance.canRecord;

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
    _chatKey = await ChatKeyService.instance.ensureChatKey(
      chatId: widget.chatId,
      retries: 4,
      delay: const Duration(milliseconds: 700),
    );

    if (_chatKey == null) {
      throw Exception(
        "Нет ключа чата. Открой этот чат на устройстве, где сообщения уже видны, и подожди пару секунд.",
      );
    }
  }

  Future<void> _loadHistory({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;

    if (!silent && mounted) {
      setState(() {
        loading = true;
        err = null;
      });
    }

    try {
      await ChatKeyService.instance.syncChatKeyForChat(widget.chatId);
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
            "sender_device_id": m["sender_device_id"],
            "created_at": m["created_at"],
            ...plain,
          });
        } catch (e) {
          debugPrint("decrypt message failed id=${m["id"]}: $e");
        }
      }

      out.sort((a, b) {
        final ai = (a["id"] as int?) ?? 0;
        final bi = (b["id"] as int?) ?? 0;
        return ai.compareTo(bi);
      });

      if (!mounted) return;
      setState(() {
        messages = out;
        loading = false;
        err = null;
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

      await ChatKeyService.instance.syncChatKeyForChat(widget.chatId);
      await _loadHistory(silent: true);
    } catch (e) {
      if (!mounted) return;
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

      final att = jsonDecode(body) as Map<String, dynamic>;

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

      await ChatKeyService.instance.syncChatKeyForChat(widget.chatId);
      await _loadHistory(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => err = e.toString());
    }
  }

  Future<void> _sendVoice() async {
    if (!_canRecordVoice || recording) return;

    bool canceled = false;

    try {
      await _ensureChatKey();

      if (!mounted) return;
      setState(() {
        err = null;
        recording = true;
      });

      await VoiceRecorderService.instance.start();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text("Запись голосового"),
            content: const Text("Идёт запись..."),
            actions: [
              TextButton(
                onPressed: () async {
                  canceled = true;
                  await VoiceRecorderService.instance.cancel();
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text("Отмена"),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text("Стоп"),
              ),
            ],
          );
        },
      );

      if (canceled) return;

      final result = await VoiceRecorderService.instance.stop();

      final file = File(result.path);
      final bytes = await file.readAsBytes();

      final fileKey = CryptoService.instance.randomBytes(32);

      final encryptedFile = await CryptoService.instance.encryptBytes(
        plaintext: bytes,
        key: fileKey,
        aad: "voice:chat:${widget.chatId}",
      );

      final req =
          http.MultipartRequest("POST", Api.instance.uri("/attachments"));
      req.headers.addAll(Session.instance.authHeaders());

      req.files.add(
        http.MultipartFile.fromBytes(
          "file",
          encryptedFile,
          filename: "voice_${DateTime.now().millisecondsSinceEpoch}.m4a.e2ee",
        ),
      );

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode >= 400) {
        throw Exception(body);
      }

      final att = jsonDecode(body) as Map<String, dynamic>;

      final payload = await CryptoService.instance.encryptJson(
        plaintext: {
          "type": "voice",
          "attachment_id": att["attachment_id"],
          "file_key_b64": base64Encode(fileKey),
          "duration_ms": result.durationMs,
          "ext": "m4a",
        },
        key: _chatKey!,
        aad: "chat:${widget.chatId}",
      );

      await Api.instance.post("/messages", {
        "chat_id": widget.chatId,
        "payload_json": payload,
        "sender_device_id": Session.instance.deviceId,
      });

      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}

      await ChatKeyService.instance.syncChatKeyForChat(widget.chatId);
      await _loadHistory(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => err = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          recording = false;
        });
      }
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

      if (response.statusCode >= 400) {
        throw Exception("${response.statusCode}: ${response.body}");
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
      if (!mounted) return;
      setState(() => err = e.toString());
    }
  }

  Future<void> _openVoice(Map<String, dynamic> msg) async {
    try {
      final id = msg["attachment_id"];
      final fileKey = base64Decode(msg["file_key_b64"]);
      final ext = (msg["ext"] ?? "m4a").toString();

      final response = await http.get(
        Api.instance.uri("/attachments/$id"),
        headers: Session.instance.authHeaders(),
      );

      if (response.statusCode >= 400) {
        throw Exception("${response.statusCode}: ${response.body}");
      }

      final plain = await CryptoService.instance.decryptBytes(
        packedJsonBytes: response.bodyBytes,
        key: Uint8List.fromList(fileKey),
      );

      final dir = await getTemporaryDirectory();
      final path = "${dir.path}/voice_$id.$ext";
      final file = File(path);
      await file.writeAsBytes(plain);

      await OpenFilex.open(path);
    } catch (e) {
      if (!mounted) return;
      setState(() => err = e.toString());
    }
  }

  Future<void> _handleOpenAttachment(Map<String, dynamic> msg) async {
    final type = (msg["type"] ?? "").toString();

    if (type == "file") {
      await _openFile(msg);
      return;
    }

    if (type == "voice") {
      await _openVoice(msg);
      return;
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
              child: Text(
                err!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(child: Text("Сообщений пока нет"))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (c, i) => MessageTile(
                          message: messages[i],
                          onOpenFile: _handleOpenAttachment,
                        ),
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _sendFile,
                  ),
                  if (_canRecordVoice)
                    IconButton(
                      icon: Icon(
                        recording ? Icons.mic : Icons.mic_none,
                        color: recording ? Colors.red : null,
                      ),
                      onPressed: recording ? null : _sendVoice,
                    ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: "Message",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}