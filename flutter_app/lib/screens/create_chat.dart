import 'package:flutter/material.dart';
import '../services/api.dart';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});
  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _members = TextEditingController();
  final _title = TextEditingController();
  bool _isGroup = false;
  String? err;

  Future<void> create() async {
    setState(() => err = null);
    try {
      final usernames = _members.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await Api.instance.post("/chats", {
        "member_usernames": usernames,
        "is_group": _isGroup,
        "title": _isGroup ? _title.text.trim() : null,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => err = e.toString());
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
              onChanged: (v) => setState(() => _isGroup = v),
              title: const Text("Group chat"),
            ),
            if (_isGroup) TextField(controller: _title, decoration: const InputDecoration(labelText: "Group title")),
            TextField(
              controller: _members,
              decoration: const InputDecoration(labelText: "Members usernames (comma separated)"),
            ),
            const SizedBox(height: 12),
            if (err != null) Text(err!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: create, child: const Text("Create")),
          ],
        ),
      ),
    );
  }
}
