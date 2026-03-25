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

      if (!mounted) return;
      setState(() {
        chats = res.cast<Map<String, dynamic>>();
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

    return chat['is_group'] == true
        ? 'Групповой чат #${chat['id']}'
        : 'Личный чат #${chat['id']}';
  }

  String _chatSubtitle(Map<String, dynamic> chat) {
    return chat['is_group'] == true
        ? 'Групповой защищённый чат'
        : 'Личный защищённый чат';
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

  @override
  Widget build(BuildContext context) {
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
          if (err != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                : chats.isEmpty
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
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: chats.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final chat = chats[index];
                            final isGroup = chat['is_group'] == true;

                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: isGroup
                                      ? AppTheme.primary.withOpacity(0.14)
                                      : const Color(0xFFE8F5E9),
                                  foregroundColor: isGroup
                                      ? AppTheme.primaryDark
                                      : const Color(0xFF2E7D32),
                                  child: Icon(
                                    isGroup
                                        ? Icons.groups_rounded
                                        : Icons.person_rounded,
                                  ),
                                ),
                                title: Text(
                                  _chatTitle(chat),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(_chatSubtitle(chat)),
                                ),
                                trailing: const Icon(Icons.chevron_right_rounded),
                                onTap: () => _openChat(chat),
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
