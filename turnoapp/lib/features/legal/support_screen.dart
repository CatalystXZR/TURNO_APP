import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/decorative_background.dart';

class SupportScreen extends StatelessWidget {
  final bool showCloseButton;

  const SupportScreen({
    super.key,
    this.showCloseButton = false,
  });

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      queryParameters: {
        'subject': 'Soporte Turno',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    if (context.mounted) {
      AppSnackbar.show(
        context,
        'No pudimos abrir tu app de correo.',
        isError: true,
      );
    }
  }

  Future<void> _openEmergencyCall(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Llamada de emergencia'),
        content: const Text(
          'Estas seguro de que deseas llamar al ${AppConstants.emergencyPhoneCL} (Carabineros)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Llamar'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final uri = Uri(scheme: 'tel', path: AppConstants.emergencyPhoneCL);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    if (context.mounted) {
      AppSnackbar.show(
        context,
        'No se pudo iniciar la llamada en este dispositivo.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soporte'),
        actions: [
          if (showCloseButton)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
              tooltip: 'Cerrar',
            ),
        ],
      ),
      body: DecorativeBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centro de soporte Turno',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Te ayudamos con cuenta, reservas, billetera y seguridad. Para emergencias presenciales usa el canal de emergencia.',
                    ),
                    const SizedBox(height: 14),
                    _ContactTile(
                      icon: Icons.email_outlined,
                      title: 'Correo de soporte',
                      subtitle: AppConstants.supportEmail,
                      actionLabel: 'Enviar correo',
                      onPressed: () => _openEmail(context),
                    ),
                    const SizedBox(height: 10),
                    _ContactTile(
                      icon: Icons.schedule_outlined,
                      title: 'Tiempo de respuesta',
                      subtitle:
                          'Respondemos en ${AppConstants.supportResponseWindow}.',
                    ),
                    const SizedBox(height: 10),
                    _ContactTile(
                      icon: Icons.emergency_outlined,
                      title: 'Emergencias en Chile',
                      subtitle:
                          'Llama al ${AppConstants.emergencyPhoneCL} (Carabineros).',
                      actionLabel: 'Llamar ahora',
                      isDanger: true,
                      onPressed: () => _openEmergencyCall(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Antes de escribirnos',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 8),
                    Text(
                        '1) Incluye correo de tu cuenta y hora aproximada del problema.'),
                    SizedBox(height: 4),
                    Text('2) Si aplica, comparte ID de reserva o turno.'),
                    SizedBox(height: 4),
                    Text('3) Describe lo que esperabas vs. lo que ocurrio.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: AppTheme.errorBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gestion de cuenta',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Si deseas eliminar tu cuenta y todos tus datos asociados, puedes hacerlo desde la seccion de privacidad y cuenta de tu perfil.',
                      style: TextStyle(
                        color: AppTheme.subtle,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/profile/edit'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: AppTheme.danger),
                      ),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Eliminar mi cuenta'),
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

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onPressed;
  final bool isDanger;

  const _ContactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onPressed,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = isDanger ? AppTheme.danger : AppTheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        color: const Color(0xFFF8FBFF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.subtle),
          ),
          if (actionLabel != null && onPressed != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onPressed,
                icon: Icon(
                  isDanger ? Icons.call_outlined : Icons.open_in_new_outlined,
                  size: 16,
                ),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
