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

  String _chatTitle(Map<String, dynamic> chat) {
    final title = chat['title']?.toString().trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    final members = _membersByChat[chat['id'] as int? ?? -1] ?? const [];
    if (chat['is_group'] == true) {
      return members.isEmpty ? 'Групповой чат' : members.map((e) => e['username']).join(', ');
    }

    for (final member in members) {
      if (member['id'] != Session.instance.userId) {
        return member['username']?.toString() ?? 'Личный чат';
      }
    }
    return 'Личный чат';
  }

  String _chatSubtitle(Map<String, dynamic> chat) {
    final members = _membersByChat[chat['id'] as int? ?? -1] ?? const [];
    if (chat['is_group'] == true) {
      if (members.isEmpty) return 'Групповой защищённый чат';
      return '${members.length} участников';
    }
    return 'Личный защищённый чат';
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatViewScreen(
          chatId: chat['id'] as int,
          title: _chatTitle(chat),
        ),
      ),
    );

    await _load();
  }

  List<Map<String, dynamic>> get _filteredChats {
    if (_search.trim().isEmpty) return chats;
    final q = _search.trim().toLowerCase();
    return chats.where((chat) {
      final title = _chatTitle(chat).toLowerCase();
      final subtitle = _chatSubtitle(chat).toLowerCase();
      return title.contains(q) || subtitle.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredChats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Защищённый чат'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateChat,
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('Новый чат'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                hintText: 'Поиск по чатам',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEECEC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  err!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Icon(
                              Icons.forum_outlined,
                              size: 56,
                              color: AppTheme.textSecondary,
                            ),
                            SizedBox(height: 16),
                            Center(
                              child: Text(
                                'Пока нет чатов',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(height: 8),
                            Center(
                              child: Text(
                                'Создайте первый защищённый чат.',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final chat = filtered[index];
                            final isGroup = chat['is_group'] == true;
                            final title = _chatTitle(chat);
                            final subtitle = _chatSubtitle(chat);
                            final avatarText = title.isNotEmpty ? title.characters.first.toUpperCase() : '#';

                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => _openChat(chat),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 26,
                                        backgroundColor: isGroup ? const Color(0x1F2AABEE) : const Color(0xFFE8F5E9),
                                        foregroundColor: isGroup ? AppTheme.primaryDark : const Color(0xFF2E7D32),
                                        child: isGroup
                                            ? const Icon(Icons.groups_rounded)
                                            : Text(
                                                avatarText,
                                                style: const TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                                    ],
                                  ),
                                ),
                              ),
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
