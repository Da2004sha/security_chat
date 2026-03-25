import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MessageTile extends StatelessWidget {
  final Map<String, dynamic> message;
  final int? myUserId;
  final Future<void> Function(Map<String, dynamic> msg)? onOpenFile;

  const MessageTile({
    super.key,
    required this.message,
    this.myUserId,
    this.onOpenFile,
  });

  String _timeLabel() {
    final raw = message['created_at']?.toString();
    if (raw == null || raw.isEmpty) return '';

    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;

    final hh = parsed.hour.toString().padLeft(2, '0');
    final mm = parsed.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final type = (message['type'] ?? 'text').toString();
    final sender = message['sender_user_id']?.toString() ?? '?';
    final isMine = myUserId != null && message['sender_user_id'] == myUserId;
    final createdAt = _timeLabel();

    final bubbleColor = isMine ? AppTheme.bubbleMine : AppTheme.bubbleOther;
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final cross =
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 6),
      bottomRight: Radius.circular(isMine ? 6 : 18),
    );

    Widget content;

    if (type == 'voice') {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
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
                  'Нажмите, чтобы открыть',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else if (type == 'file') {
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
                  color: Colors.black.withOpacity(0.05),
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
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onOpenFile == null ? null : () => onOpenFile!(message),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(0, 0),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Открыть файл'),
          ),
        ],
      );
    } else {
      final text = (message['text'] ?? '').toString();
      content = Text(
        text,
        style: const TextStyle(fontSize: 15, height: 1.35),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: InkWell(
            borderRadius: radius,
            onTap: (type == 'file' || type == 'voice') && onOpenFile != null
                ? () => onOpenFile!(message)
                : null,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                border: Border.all(color: AppTheme.border),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 8,
                    offset: Offset(0, 2),
                    color: Color(0x0A000000),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: cross,
                children: [
                  if (!isMine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Пользователь $sender',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ),
                  content,
                  const SizedBox(height: 8),
                  Text(
                    createdAt,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
