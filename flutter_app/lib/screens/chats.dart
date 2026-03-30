import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/chat_key_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
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
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppTheme.primary),
                  ),
                ),
              ),
            ),
            if (err != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE9E9),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  err!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'Пока нет чатов',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemBuilder: (context, index) {
                            final chat = filtered[index];
                            final chatId = chat['id'] as int;
                            final title = (chat['title'] ?? 'Чат').toString();

                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
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
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: AppTheme.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFE8F5E9),
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          title.isNotEmpty
                                              ? title.characters.first.toUpperCase()
                                              : 'Ч',
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF2E7D32),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _chatSubtitle(chat),
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: AppTheme.textSecondary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.more_vert_rounded,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemCount: filtered.length,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}