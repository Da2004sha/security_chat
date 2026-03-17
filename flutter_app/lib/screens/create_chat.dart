import 'package:flutter/material.dart';

import '../services/chat_key_service.dart';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _members = TextEditingController();
  final _title = TextEditingController();

  bool _isGroup = false;
  bool _busy = false;
  String? err;

  @override
  void dispose() {
    _members.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (_busy) return;

    setState(() {
      err = null;
      _busy = true;
    });

    try {
      final usernames = _members.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (usernames.isEmpty) {
        throw Exception("Укажи хотя бы одного участника");
      }

      await ChatKeyService.instance.createChatAndDistributeKey(
        memberUsernames: usernames,
        isGroup: _isGroup,
        title: _isGroup ? _title.text.trim() : null,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create chat")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              value: _isGroup,
              onChanged: _busy ? null : (v) => setState(() => _isGroup = v),
              title: const Text("Group chat"),
            ),
            if (_isGroup)
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: "Group title"),
              ),
            TextField(
              controller: _members,
              decoration: const InputDecoration(
                labelText: "Members usernames (comma separated)",
              ),
            ),
            const SizedBox(height: 12),
            if (err != null)
              Text(err!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : create,
              child: Text(_busy ? "Creating..." : "Create"),
            ),
          ],
        ),
      ),
    );
  }
}