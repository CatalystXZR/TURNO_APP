import 'package:flutter/material.dart';

import '../../app/theme.dart';

class ReviewDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String confirmLabel;

  const ReviewDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
  });

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  int _stars = 5;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitle),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                onPressed: () => setState(() => _stars = value),
                icon: Icon(
                  value <= _stars ? Icons.star : Icons.star_border,
                  color: value <= _stars
                      ? const Color(0xFFFFC945)
                      : AppTheme.inactiveStep,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Comentario (opcional)',
              hintText: 'Comparte tu experiencia para la comunidad',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(<String, dynamic>{
              'stars': _stars,
              'comment': _commentController.text.trim(),
            });
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
