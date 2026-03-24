import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/chat_key_service.dart';
import '../services/session.dart';
import 'chat_view.dart';
import 'create_chat.dart';
import 'login.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  bool loading = true;
  String? err;
  List<Map<String, dynamic>> chats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      err = null;
    });

    try {
      await ChatKeyService.instance.importMyChatKeys();

      final res = await Api.instance.getList("/chats");

      if (!mounted) return;
      setState(() {
        chats = res.cast<Map<String, dynamic>>();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        err = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _openCreateChat() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateChatScreen()),
    );

    if (created == true) {
      await _load();
    }
  }

  Future<void> _logout() async {
    await Session.instance.logout();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  String _chatTitle(Map<String, dynamic> chat) {
    final title = chat["title"]?.toString().trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return "Chat #${chat["id"]}";
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatViewScreen(
          chatId: chat["id"] as int,
          title: _chatTitle(chat),
        ),
      ),
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chats"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateChat,
        child: const Icon(Icons.add),
      ),
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
                : chats.isEmpty
                    ? const Center(child: Text("No chats yet"))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: chats.length,
                          itemBuilder: (context, index) {
                            final chat = chats[index];
                            return ListTile(
                              title: Text(_chatTitle(chat)),
                              subtitle: Text(
                                chat["is_group"] == true
                                    ? "Group"
                                    : "Direct chat",
                              ),
                              onTap: () => _openChat(chat),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}