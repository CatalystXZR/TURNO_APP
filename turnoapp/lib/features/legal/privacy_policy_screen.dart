import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../shared/widgets/decorative_background.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  final bool showCloseButton;

  const PrivacyPolicyScreen({
    super.key,
    this.showCloseButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <_PrivacySection>[
      const _PrivacySection(
        title: 'Datos que recolectamos',
        bullets: [
          'Datos de cuenta: nombre, correo y universidad.',
          'Datos de perfil operativo: foto, patente, modelo de vehiculo y contacto de emergencia cuando aplican.',
          'Datos de uso de la plataforma: reservas, publicaciones, cancelaciones y eventos de seguridad.',
          'Datos de billetera: movimientos, recargas y retiros asociados a tu cuenta.',
        ],
      ),
      const _PrivacySection(
        title: 'Para que usamos tus datos',
        bullets: [
          'Operar el servicio de movilidad universitaria y coordinar viajes entre pasajeros y conductores.',
          'Aplicar reglas de seguridad, no-show, strikes y conciliacion financiera.',
          'Brindar soporte, responder reportes y cumplir obligaciones regulatorias.',
        ],
      ),
      const _PrivacySection(
        title: 'Como compartimos informacion',
        bullets: [
          'Mostramos a otros usuarios solo los datos necesarios para concretar un viaje seguro.',
          'Podemos compartir informacion con proveedores de infraestructura y pagos para operar Turno.',
          'No vendemos datos personales a terceros.',
        ],
      ),
      const _PrivacySection(
        title: 'Retencion y control de datos',
        bullets: [
          'Conservamos datos por el tiempo necesario para operar la plataforma y resolver disputas de seguridad o pagos.',
          'Puedes editar tu perfil en cualquier momento desde la app.',
          'Puedes solicitar eliminacion de cuenta desde Perfil > Editar perfil > Eliminar mi cuenta.',
        ],
      ),
      const _PrivacySection(
        title: 'Contacto de privacidad',
        bullets: [
          'Correo de contacto: ${AppConstants.supportEmail}',
          'Tiempo de respuesta estimado: ${AppConstants.supportResponseWindow}.',
          'Telefono de emergencias Chile: ${AppConstants.emergencyPhoneCL}.',
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Politica de privacidad'),
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
                      'Turno - Politica de privacidad',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Version ${AppConstants.privacyPolicyVersion} · Actualizada ${AppConstants.privacyPolicyLastUpdated}',
                      style: const TextStyle(
                        color: AppTheme.subtle,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Esta politica describe como Turno recopila, usa y protege la informacion personal cuando utilizas la plataforma.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...sections.map(
              (section) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        ...section.bullets.map(
                          (bullet) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.shield_outlined,
                                    size: 16,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(bullet)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySection {
  final String title;
  final List<String> bullets;

  const _PrivacySection({required this.title, required this.bullets});
}
