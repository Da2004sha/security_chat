import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MessageTile extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final String senderName;
  final bool showSender;
  final Future<void> Function(Map<String, dynamic> msg)? onOpenFile;

  // 🔥 новое
  final VoidCallback? onDeleteMessage;

  const MessageTile({
    super.key,
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.showSender,
    this.onOpenFile,
    this.onDeleteMessage,
  });

  static DateTime? parseMoscowDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;

    final utc = parsed.isUtc
        ? parsed
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );

    return utc.add(const Duration(hours: 3));
  }

  static String formatMoscowTime(String? raw) {
    final moscow = parseMoscowDate(raw);
    if (moscow == null) return '';
    final hh = moscow.hour.toString().padLeft(2, '0');
    final mm = moscow.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final type = (message['type'] ?? 'text').toString();
    final createdAt = formatMoscowTime(message['created_at']?.toString());
    final verified = message['verified'] as bool?;

    final bubbleColor = isMine ? AppTheme.bubbleMine : AppTheme.bubbleOther;
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final cross = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 6),
      bottomRight: Radius.circular(isMine ? 6 : 18),
    );

    Widget content;

    // 🔥 УДАЛЁННОЕ СООБЩЕНИЕ
    if (type == 'deleted') {
      content = const Text(
        'Сообщение удалено',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Colors.grey,
        ),
      );
    }

    // голос
    else if (type == 'voice') {
      final durationMs = (message['duration_ms'] as num?)?.toInt() ?? 0;
      final seconds = (durationMs / 1000).round();
      final durationLabel =
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0x1F2AABEE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Голосовое сообщение',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  durationLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // файл
    else if (type == 'file') {
      final name = (message['name'] ?? 'Файл').toString();

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0x0D000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insert_drive_file_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onOpenFile == null ? null : () => onOpenFile!(message),
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new_rounded,
                      size: 18, color: AppTheme.primary),
                  SizedBox(width: 6),
                  Text(
                    'Открыть файл',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // текст
    else {
      final text = (message['text'] ?? '').toString();
      content = Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.35,
          color: AppTheme.textPrimary,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            color: bubbleColor,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,

              // 🔥 LONG PRESS УДАЛЕНИЕ
              onLongPress: isMine && onDeleteMessage != null
                  ? () {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => SafeArea(
                          child: ListTile(
                            leading: const Icon(Icons.delete, color: Colors.red),
                            title: const Text('Удалить сообщение'),
                            onTap: () {
                              Navigator.pop(context);
                              onDeleteMessage!();
                            },
                          ),
                        ),
                      );
                    }
                  : null,

              onTap: (type == 'file' || type == 'voice') &&
                      onOpenFile != null
                  ? () => onOpenFile!(message)
                  : null,

              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: AppTheme.border),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 10,
                      offset: Offset(0, 2),
                      color: Color(0x12000000),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: cross,
                  children: [
                    if (showSender && !isMine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          senderName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                    content,
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (verified == true) ...[
                          const Icon(Icons.verified_user_rounded,
                              size: 14, color: AppTheme.primary),
                          const SizedBox(width: 4),
                        ] else if (verified == false) ...[
                          const Icon(Icons.warning_amber_rounded,
                              size: 14, color: AppTheme.danger),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          createdAt,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.done_all_rounded,
                              size: 15, color: AppTheme.primary),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}