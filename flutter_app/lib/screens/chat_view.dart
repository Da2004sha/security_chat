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
import '../theme/app_theme.dart';
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
  final _scrollController = ScrollController();

  bool loading = true;
  bool _refreshing = false;
  bool recording = false;
  String? err;

  List<Map<String, dynamic>> messages = [];
  Uint8List? _chatKey;
  Map<int, String> _usernamesById = {};
  List<Map<String, dynamic>> _members = [];

  Timer? _timer;
  bool _shouldScrollAfterBuild = false;

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
    _scrollController.dispose();
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
        'Нет ключа чата. Открой этот чат на устройстве, где сообщения уже видны, и подожди пару секунд.',
      );
    }
  }

  Future<void> _loadMembers() async {
    final members =
        await Api.instance.getList('/chats/${widget.chatId}/members');
    final usernamesById = <int, String>{};

    for (final raw in members.cast<Map<String, dynamic>>()) {
      final id = raw['id'];
      final username = raw['username']?.toString();
      if (id is int && username != null && username.isNotEmpty) {
        usernamesById[id] = username;
      }
    }

    _members = members.cast<Map<String, dynamic>>();
    _usernamesById = usernamesById;
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) < 120;
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;

    final target = _scrollController.position.maxScrollExtent + 80;

    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  bool _sameMessages(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;

    for (var i = 0; i < a.length; i++) {
      final aMsg = a[i];
      final bMsg = b[i];

      if (aMsg['id'] != bMsg['id']) return false;
      if (aMsg['created_at'] != bMsg['created_at']) return false;
      if (aMsg['text'] != bMsg['text']) return false;
      if (aMsg['type'] != bMsg['type']) return false;
      if (aMsg['sender_user_id'] != bMsg['sender_user_id']) return false;
      if (aMsg['attachment_id'] != bMsg['attachment_id']) return false;
      if (aMsg['name'] != bMsg['name']) return false;
      if (aMsg['duration_ms'] != bMsg['duration_ms']) return false;
    }

    return true;
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
      await _loadMembers();

      final res =
          await Api.instance.getList('/chats/${widget.chatId}/messages?limit=100');

      final out = <Map<String, dynamic>>[];

      for (final m in res.cast<Map<String, dynamic>>()) {
        try {
          final plain = await CryptoService.instance.decryptJson(
            payloadJson: m['payload_json'],
            key: _chatKey!,
          );

          final senderId = m['sender_user_id'] as int?;
          out.add({
            'id': m['id'],
            'sender_user_id': senderId,
            'sender_device_id': m['sender_device_id'],
            'created_at': m['created_at'],
            'sender_username': _usernamesById[senderId ?? -1] ?? 'Пользователь',
            ...plain,
          });
        } catch (e) {
          debugPrint('decrypt message failed id=${m['id']}: $e');
        }
      }

      out.sort((a, b) {
        final ai = (a['id'] as int?) ?? 0;
        final bi = (b['id'] as int?) ?? 0;
        return ai.compareTo(bi);
      });

      if (!mounted) return;

      final hadMessages = messages.isNotEmpty;
      final oldLastId = hadMessages ? messages.last['id'] : null;
      final newLastId = out.isNotEmpty ? out.last['id'] : null;
      final changed = !_sameMessages(messages, out);
      final nearBottom = _isNearBottom();

      if (!changed) {
        if (!silent) {
          setState(() {
            loading = false;
            err = null;
          });
        }
        return;
      }

      final shouldAutoScroll =
          !hadMessages || oldLastId != newLastId ? nearBottom || !silent : false;

      setState(() {
        messages = out;
        loading = false;
        err = null;
        _shouldScrollAfterBuild = shouldAutoScroll;
      });

      if (_shouldScrollAfterBuild) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToBottom(animated: silent);
          _shouldScrollAfterBuild = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        err = e.toString().replaceFirst('Exception: ', '');
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
          'type': 'text',
          'text': text,
        },
        key: _chatKey!,
        aad: 'chat:${widget.chatId}',
      );

      await Api.instance.post('/messages', {
        'chat_id': widget.chatId,
        'payload_json': payload,
        'sender_device_id': Session.instance.deviceId,
      });

      _shouldScrollAfterBuild = true;
      await ChatKeyService.instance.syncChatKeyForChat(widget.chatId);
      await _loadHistory(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => err = e.toString().replaceFirst('Exception: ', ''));
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
        aad: 'file:chat:${widget.chatId}',
      );

      final req = http.MultipartRequest('POST', Api.instance.uri('/attachments'));
      req.headers.addAll(Session.instance.authHeaders());

      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          encryptedFile,
          filename: '${file.name}.e2ee',
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
          'type': 'file',
          'attachment_id': att['attachment_id'],
          'name': file.name,
          'file_key_b64': fileKeyB64,
        },
        key: _chatKey!,
        aad: 'chat:${widget.chatId}',
      );

      await Api.instance.post('/messages', {
        'chat_id': widget.chatId,
        'payload_json': payload,
        'sender_device_id': Session.instance.deviceId,
      });

      _shouldScrollAfterBuild = true;
      await ChatKeyService.instance.syncChatKeyForChat(widget.chatId);
      await _loadHistory(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => err = e.toString().replaceFirst('Exception: ', ''));
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
            title: const Text('Запись голосового сообщения'),
            content:
                const Text('Идёт запись. Нажми «Стоп», чтобы отправить.'),
            actions: [
              TextButton(
                onPressed: () async {
                  canceled = true;
                  await VoiceRecorderService.instance.cancel();
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Стоп'),
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
        aad: 'voice:chat:${widget.chatId}',
      );

      final req = http.MultipartRequest('POST', Api.instance.uri('/attachments'));
      req.headers.addAll(Session.instance.authHeaders());

      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          encryptedFile,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a.e2ee',
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
          'type': 'voice',
          'attachment_id': att['attachment_id'],
          'file_key_b64': base64Encode(fileKey),
          'duration_ms': result.durationMs,
          'ext': 'm4a',
          'name': 'Голосовое сообщение',
        },
        key: _chatKey!,
        aad: 'chat:${widget.chatId}',
      );

      await Api.instance.post('/messages', {
        'chat_id': widget.chatId,
        'payload_json': payload,
        'sender_device_id': Session.instance.deviceId,
      });

      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}

      _shouldScrollAfterBuild = true;
      await ChatKeyService.instance.syncChatKeyForChat(widget.chatId);
      await _loadHistory(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => err = e.toString().replaceFirst('Exception: ', ''));
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
      final id = msg['attachment_id'];
      final fileKey = base64Decode(msg['file_key_b64']);

      final response = await http.get(
        Api.instance.uri('/attachments/$id'),
        headers: Session.instance.authHeaders(),
      );

      if (response.statusCode >= 400) {
        throw Exception('${response.statusCode}: ${response.body}');
      }

      final plain = await CryptoService.instance.decryptBytes(
        packedJsonBytes: response.bodyBytes,
        key: Uint8List.fromList(fileKey),
      );

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${msg['name']}';
      final file = File(path);
      await file.writeAsBytes(plain);

      await OpenFilex.open(path);
    } catch (e) {
      if (!mounted) return;
      setState(() => err = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openVoice(Map<String, dynamic> msg) async {
    try {
      final id = msg['attachment_id'];
      final fileKey = base64Decode(msg['file_key_b64']);
      final ext = (msg['ext'] ?? 'm4a').toString();

      final response = await http.get(
        Api.instance.uri('/attachments/$id'),
        headers: Session.instance.authHeaders(),
      );

      if (response.statusCode >= 400) {
        throw Exception('${response.statusCode}: ${response.body}');
      }

      final plain = await CryptoService.instance.decryptBytes(
        packedJsonBytes: response.bodyBytes,
        key: Uint8List.fromList(fileKey),
      );

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_$id.$ext';
      final file = File(path);
      await file.writeAsBytes(plain);

      await OpenFilex.open(path);
    } catch (e) {
      if (!mounted) return;
      setState(() => err = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _handleOpenAttachment(Map<String, dynamic> msg) async {
    final type = (msg['type'] ?? '').toString();

    if (type == 'file') {
      await _openFile(msg);
      return;
    }

    if (type == 'voice') {
      await _openVoice(msg);
      return;
    }
  }

  String _chatSubtitle() {
    if (_members.isEmpty) return 'Защищённая переписка';

    if (_members.length == 2) {
      final other = _members.firstWhere(
        (m) => m['id'] != Session.instance.userId,
        orElse: () => _members.first,
      );
      return other['username']?.toString() ?? 'Личный чат';
    }

    return '${_members.length} участников';
  }

  String _dateHeaderText(String? raw) {
    final date = MessageTile.parseMoscowDate(raw);
    if (date == null) return '';

    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final msgDate = DateTime(date.year, date.month, date.day);
    final nowDate = DateTime(now.year, now.month, now.day);
    final diff = nowDate.difference(msgDate).inDays;

    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';

    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];

    return '${date.day} ${months[date.month - 1]}';
  }

  bool _needsDateHeader(int index) {
    if (index == 0) return true;

    final current =
        MessageTile.parseMoscowDate(messages[index]['created_at']?.toString());
    final previous = MessageTile.parseMoscowDate(
      messages[index - 1]['created_at']?.toString(),
    );

    if (current == null || previous == null) return false;

    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  bool _shouldShowSender(int index) {
    final current = messages[index];

    if (current['sender_user_id'] == Session.instance.userId) return false;
    if (index == 0) return true;
    if (_needsDateHeader(index)) return true;

    final previous = messages[index - 1];
    return previous['sender_user_id'] != current['sender_user_id'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              _chatSubtitle(),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Container(
        color: AppTheme.chatBackground,
        child: Column(
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
                  : messages.isEmpty
                      ? const Center(
                          child: Text(
                            'Сообщений пока нет',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                          itemCount: messages.length,
                          itemBuilder: (context, i) {
                            final msg = messages[i];
                            final showDateHeader = _needsDateHeader(i);
                            final senderName =
                                msg['sender_username']?.toString() ??
                                'Пользователь';
                            final isMine =
                                msg['sender_user_id'] == Session.instance.userId;
                            final showSender = _shouldShowSender(i);

                            return Column(
                              children: [
                                if (showDateHeader)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: AppTheme.border,
                                        ),
                                      ),
                                      child: Text(
                                        _dateHeaderText(
                                          msg['created_at']?.toString(),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                MessageTile(
                                  message: msg,
                                  isMine: isMine,
                                  senderName: senderName,
                                  showSender: showSender,
                                  onOpenFile: _handleOpenAttachment,
                                ),
                              ],
                            );
                          },
                        ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Прикрепить файл',
                      icon: const Icon(Icons.attach_file_rounded),
                      onPressed: _sendFile,
                    ),
                    if (_canRecordVoice)
                      IconButton(
                        tooltip: 'Голосовое сообщение',
                        icon: Icon(
                          recording
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: recording ? Colors.red : null,
                        ),
                        onPressed: recording ? null : _sendVoice,
                      ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: const InputDecoration(
                          hintText: 'Сообщение',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _sendText,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(52, 52),
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.send_rounded),
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