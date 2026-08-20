import 'package:flutter/material.dart';
import '../models/message.dart';

const Map<String, String> moodIcons = {
  'happy': '😊',
  'neutral': '😐',
  'sad': '😢',
  'angry': '😤',
  'excited': '🤩',
  'calm': '😌',
};

class BarrageItem extends StatelessWidget {
  final Message message;
  final VoidCallback onTap;

  const BarrageItem({
    super.key,
    required this.message,
    required this.onTap,
  });

  Color _parseColor(String colorStr) {
    try {
      if (colorStr.startsWith('#')) {
        return Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
      }
      if (colorStr.startsWith('rgba')) {
        final parts = colorStr
            .replaceAll('rgba(', '')
            .replaceAll(')', '')
            .split(',');
        return Color.fromARGB(
          (double.parse(parts[3].trim()) * 255).toInt(),
          int.parse(parts[0].trim()),
          int.parse(parts[1].trim()),
          int.parse(parts[2].trim()),
        );
      }
    } catch (_) {}
    return Colors.white;
  }

  Color _parseBgColor(String bgStr) {
    try {
      if (bgStr.startsWith('rgba')) {
        final parts = bgStr
            .replaceAll('rgba(', '')
            .replaceAll(')', '')
            .split(',');
        return Color.fromARGB(
          (double.parse(parts[3].trim()) * 255).toInt(),
          int.parse(parts[0].trim()),
          int.parse(parts[1].trim()),
          int.parse(parts[2].trim()),
        );
      }
      if (bgStr.startsWith('#')) {
        return Color(int.parse(bgStr.replaceFirst('#', '0xFF')));
      }
    } catch (_) {}
    return Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    final color = message.isAnonymous
        ? Colors.white70
        : _parseColor(message.color);
    final bgColor = _parseBgColor(message.bgColor);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              moodIcons[message.mood] ?? '',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                message.content,
                style: TextStyle(color: color, fontSize: 14),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '@${message.authorName}',
              style: TextStyle(
                color: color.withOpacity(0.6),
                fontSize: 10,
              ),
            ),
            if (message.likesCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                '❤️${message.likesCount}',
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
