import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/report_service.dart';
import 'app_snackbar.dart';

class ReportUserDialog extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;
  final String? bookingId;

  const ReportUserDialog({
    super.key,
    required this.reportedUserId,
    required this.reportedUserName,
    this.bookingId,
  });

  @override
  State<ReportUserDialog> createState() => _ReportUserDialogState();
}

class _ReportUserDialogState extends State<ReportUserDialog> {
  final _reportService = ReportService();
  final _detailsController = TextEditingController();
  String _selectedCategory = 'harassment';
  bool _sending = false;

  static const _categories = [
    ('harassment', 'Acoso o comportamiento inapropiado', Icons.report_outlined),
    ('fake_profile', 'Perfil falso o informacion enganosa', Icons.person_off_outlined),
    ('dangerous_driving', 'Conduccion peligrosa o temeraria', Icons.warning_amber_outlined),
    ('passenger_misconduct', 'Mal comportamiento de pasajero', Icons.groups_outlined),
    ('no_show', 'No se presento', Icons.event_busy_outlined),
    ('other', 'Otro motivo', Icons.more_horiz_outlined),
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      await _reportService.reportUser(
        reportedUserId: widget.reportedUserId,
        reasonCategory: _selectedCategory,
        details: _detailsController.text.trim().isNotEmpty
            ? _detailsController.text.trim()
            : null,
        bookingId: widget.bookingId,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        AppSnackbar.show(
          context,
          'Reporte enviado. Gracias por ayudarnos a mantener la comunidad segura.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          'No pudimos enviar el reporte. Intenta nuevamente.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reportar a ${widget.reportedUserName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona el motivo del reporte:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            ..._categories.map(
              (cat) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: RadioListTile<String>(
                  value: cat.$1,
                  groupValue: _selectedCategory,
                  onChanged: (v) => setState(() => _selectedCategory = v!),
                  title: Row(
                    children: [
                      Icon(cat.$3, size: 18, color: AppTheme.subtle),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cat.$2,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _detailsController,
              decoration: const InputDecoration(
                labelText: 'Detalles adicionales (opcional)',
                hintText: 'Describe lo sucedido para ayudarnos a evaluar...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _sending ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
          ),
          child: Text(_sending ? 'Enviando...' : 'Enviar reporte'),
        ),
      ],
    );
  }
}
