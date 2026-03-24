import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/chat_key_service.dart';
import '../services/crypto_service.dart';
import '../services/session.dart';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _membersController = TextEditingController();
  final _titleController = TextEditingController();

  bool _busy = false;
  bool _isGroup = false;
  String? _err;

  @override
  void dispose() {
    _membersController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  List<String> _parseMembers() {
    return _membersController.text
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _create() async {
    if (_busy) return;

    final members = _parseMembers();
    final title = _titleController.text.trim();

    if (members.isEmpty) {
      setState(() {
        _err = "Укажи хотя бы одного пользователя";
      });
      return;
    }

    if (_isGroup && title.isEmpty) {
      setState(() {
        _err = "Для группового чата укажи название";
      });
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      final result = await Api.instance.post("/chats", {
        "member_usernames": members,
        "is_group": _isGroup,
        "title": title.isEmpty ? null : title,
      });

      final chatId = result["id"] as int;

      final chatKey = CryptoService.instance.randomBytes(32);
      await Session.instance.saveChatKey(chatId, chatKey);

      await ChatKeyService.instance.publishChatKeyToAllParticipants(
        chatId: chatId,
        chatKey: chatKey,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create chat"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _err!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Group chat"),
              value: _isGroup,
              onChanged: _busy
                  ? null
                  : (v) {
                      setState(() {
                        _isGroup = v;
                      });
                    },
            ),
            if (_isGroup)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _titleController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: "Group title",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            TextField(
              controller: _membersController,
              enabled: !_busy,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Usernames",
                hintText: "user1, user2",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Укажи username через запятую",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(_busy ? "Creating..." : "Create"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}