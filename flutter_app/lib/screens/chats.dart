import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/chat_key_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import 'chat_view.dart';
import 'create_chat.dart';
import 'login.dart';
import 'change_password.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  bool loading = true;
  String? err;
  List<Map<String, dynamic>> chats = [];
  Map<int, List<Map<String, dynamic>>> _membersByChat = {};
  String _search = '';

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

      final res = await Api.instance.getList('/chats');
      final loadedChats = res.cast<Map<String, dynamic>>();
      final membersByChat = <int, List<Map<String, dynamic>>>{};

      for (final chat in loadedChats) {
        final id = chat['id'];
        if (id is int) {
          try {
            final members = await Api.instance.getList('/chats/$id/members');
            membersByChat[id] = members.cast<Map<String, dynamic>>();
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        chats = loadedChats;
        _membersByChat = membersByChat;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        err = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  Future<void> _deleteChat(int chatId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить чат'),
        content: const Text('Вы уверены? Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Api.instance.delete('/chats/$chatId');

      // удаляем ключ чата с устройства
      await Session.instance.deleteChatKey(chatId);

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка удаления: $e')),
      );
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

  String _chatSubtitle(Map<String, dynamic> chat) {
    final id = chat['id'];
    if (id is! int) return 'Личный защищённый чат';

    final members = _membersByChat[id] ?? [];
    if (members.isEmpty) return 'Личный защищённый чат';

    final otherUsers = members
        .where((m) => m['id'] != Session.instance.userId)
        .map((m) => (m['username'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();

    if (otherUsers.isEmpty) return 'Личный защищённый чат';
    return otherUsers.join(', ');
  }

  List<Map<String, dynamic>> get _filteredChats {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return chats;

    return chats.where((chat) {
      final title = (chat['title'] ?? '').toString().toLowerCase();
      final subtitle = _chatSubtitle(chat).toLowerCase();
      return title.contains(q) || subtitle.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredChats;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Защищённый чат'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
  icon: const Icon(Icons.lock_reset),
  onPressed: () {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
  },
),
          
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateChat,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Новый чат'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Поиск по чатам',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('Пока нет чатов'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final chat = filtered[index];
                            final chatId = chat['id'] as int;
                            final title = (chat['title'] ?? 'Чат').toString();

                            return ListTile(
                              title: Text(title),
                              subtitle: Text(_chatSubtitle(chat)),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatViewScreen(
                                      chatId: chatId,
                                      title: title,
                                    ),
                                  ),
                                );
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _deleteChat(chatId);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Удалить чат'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}