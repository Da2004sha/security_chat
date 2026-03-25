import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/chat_key_service.dart';
import '../services/crypto_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';

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
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _create() async {
    if (_busy) return;

    FocusScope.of(context).unfocus();

    final members = _parseMembers();
    final title = _titleController.text.trim();

    if (members.isEmpty) {
      setState(() {
        _err = 'Укажи хотя бы одного пользователя';
      });
      return;
    }

    if (_isGroup && title.isEmpty) {
      setState(() {
        _err = 'Для группового чата укажи название';
      });
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      final result = await Api.instance.post('/chats', {
        'member_usernames': members,
        'is_group': _isGroup,
        'title': title.isEmpty ? null : title,
      });

      final chatId = result['id'] as int;

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
        _err = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый чат')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Создание чата',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Можно создать личный или групповой защищённый чат и задать ему название.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_err != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEECEC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _err!,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Групповой чат',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Включите, если нужно несколько участников',
                      ),
                      value: _isGroup,
                      onChanged: _busy
                          ? null
                          : (v) {
                              setState(() {
                                _isGroup = v;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: _isGroup
                            ? 'Название группового чата'
                            : 'Название чата',
                        hintText: _isGroup
                            ? 'Например: Отдел разработки'
                            : 'Например: Алексей',
                        prefixIcon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _membersController,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Участники',
                        hintText: 'user1, user2',
                        prefixIcon: Icon(Icons.group_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Укажи логины пользователей через запятую.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _create,
                      child: Text(_busy ? 'Создание...' : 'Создать чат'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
