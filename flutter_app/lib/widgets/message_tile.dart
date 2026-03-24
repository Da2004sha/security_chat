import 'package:flutter/material.dart';

class MessageTile extends StatelessWidget {
  final Map<String, dynamic> message;
  final Future<void> Function(Map<String, dynamic> msg)? onOpenFile;

  const MessageTile({
    super.key,
    required this.message,
    this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final type = (message["type"] ?? "text").toString();

    final sender = message["sender_user_id"]?.toString() ?? "?";
    final createdAt = message["created_at"]?.toString() ?? "";

    // =========================
    // 🎤 VOICE MESSAGE
    // =========================
    if (type == "voice") {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: onOpenFile == null ? null : () => onOpenFile!(message),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_arrow),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Voice message",
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  Text(
                    createdAt,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // =========================
    // 📎 FILE
    // =========================
    if (type == "file") {
      final name = (message["name"] ?? "file").toString();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "📎 $name",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        createdAt,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.5),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed:
                          onOpenFile == null ? null : () => onOpenFile!(message),
                      child: const Text("Открыть"),
                    )
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "from user $sender",
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // =========================
    // 💬 TEXT
    // =========================
    final text = (message["text"] ?? "").toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 6),
              Text(
                createdAt,
                style: TextStyle(
                  color: Colors.black.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "from user $sender",
                style: TextStyle(
                  color: Colors.black.withOpacity(0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}