/**
 *
 * Project: TurnoApp
 *
 * Original Concept: Agustin Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matias Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../../providers/home_provider.dart';
import '../../providers/in_app_notification_provider.dart';
import '../../providers/service_providers.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/decorative_background.dart';
import '../../shared/widgets/loading_overlay.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    Future.microtask(() => ref.read(homeProvider.notifier).load());
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await ref.read(homeProvider.notifier).load();
    final state = ref.read(homeProvider);
    if (!mounted || state.errorMessage == null) return;
    AppSnackbar.show(context, state.errorMessage!, isError: true);
    ref.read(homeProvider.notifier).clearError();
  }

  Future<void> _toggleRole() async {
    final state = ref.read(homeProvider);
    final profile = state.profile;
    if (profile == null || state.switchingRole) return;

    final newMode = profile.roleMode == RoleMode.driver
        ? RoleMode.passenger
        : RoleMode.driver;

    if (newMode == RoleMode.driver) {
      if (!profile.acceptedTerms) {
        if (mounted) {
          AppSnackbar.show(
            context,
            'Debes aceptar terminos para activar modo conductor.',
            isError: true,
          );
        }
        return;
      }
      if (!profile.hasValidLicense) {
        if (mounted) {
          AppSnackbar.show(
            context,
            'Debes declarar licencia vigente para activar modo conductor.',
            isError: true,
          );
        }
        return;
      }

      final hasVehicleData = _hasCompleteDriverVehicleData(profile);
      if (!hasVehicleData) {
        final completed = await _promptDriverVehicleRequirements(profile);
        if (!completed) return;

        await _load();
        final refreshed = ref.read(homeProvider).profile;
        if (!mounted || refreshed == null) return;

        final readyNow = refreshed.hasValidLicense &&
            _hasCompleteDriverVehicleData(refreshed);
        if (!readyNow) {
          if (mounted) {
            AppSnackbar.show(
              context,
              'Debes completar todos los datos del vehiculo para activar modo conductor.',
              isError: true,
            );
          }
          return;
        }
      }

      final driverSuspendedActive =
          profile.suspendedUntil?.isAfter(DateTime.now()) ?? false;
      final vehicleSuspendedActive =
          profile.vehicleSuspendedUntil?.isAfter(DateTime.now()) ?? false;

      if (driverSuspendedActive || vehicleSuspendedActive) {
        final until = DateFormat('d MMM y', 'es').format(
          driverSuspendedActive
              ? profile.suspendedUntil!
              : profile.vehicleSuspendedUntil!,
        );
        if (mounted) {
          AppSnackbar.show(
            context,
            'Tu perfil conductor esta suspendido hasta $until por strikes.',
            isError: true,
          );
        }
        return;
      }
    }

    try {
      await ref.read(homeProvider.notifier).setRoleMode(newMode);
      if (!mounted) return;
      AppSnackbar.show(
        context,
        newMode == RoleMode.driver
            ? 'Modo conductor activado'
            : 'Modo pasajero activado',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos cambiar tu modo ahora.',
        ),
        isError: true,
      );
    }
  }

  bool _hasCompleteDriverVehicleData(UserProfile profile) {
    return (profile.vehicleBrand?.trim().isNotEmpty ?? false) &&
        (profile.vehicleModel?.trim().isNotEmpty ?? false) &&
        (profile.vehicleVersion?.trim().isNotEmpty ?? false) &&
        ((profile.vehicleDoors ?? 0) >= 2) &&
        ((profile.vehicleDoors ?? 0) <= 6) &&
        (profile.vehiclePlate?.trim().isNotEmpty ?? false);
  }

  Future<bool> _promptDriverVehicleRequirements(UserProfile profile) async {
    final fullNameController =
        TextEditingController(text: profile.fullName ?? '');
    final brandController =
        TextEditingController(text: profile.vehicleBrand ?? '');
    final modelController =
        TextEditingController(text: profile.vehicleModel ?? '');
    final versionController =
        TextEditingController(text: profile.vehicleVersion ?? '');
    final doorsController = TextEditingController(
      text: profile.vehicleDoors != null ? '${profile.vehicleDoors}' : '',
    );
    final plateController =
        TextEditingController(text: profile.vehiclePlate ?? '');
    var hasLicense = profile.hasValidLicense;
    final formKey = GlobalKey<FormState>();
    var saving = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Completa datos para modo conductor',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Estos datos son obligatorios para activar el modo conductor.',
                        style: TextStyle(color: AppTheme.subtle),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: fullNameController,
                        decoration:
                            const InputDecoration(labelText: 'Nombre completo'),
                        validator: (v) => (v?.trim().length ?? 0) >= 3
                            ? null
                            : 'Nombre requerido',
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: brandController,
                        decoration: const InputDecoration(labelText: 'Marca'),
                        validator: (v) => (v?.trim().isNotEmpty ?? false)
                            ? null
                            : 'Marca requerida',
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: modelController,
                        decoration: const InputDecoration(labelText: 'Modelo'),
                        validator: (v) => (v?.trim().isNotEmpty ?? false)
                            ? null
                            : 'Modelo requerido',
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: versionController,
                        decoration: const InputDecoration(labelText: 'Version'),
                        validator: (v) => (v?.trim().isNotEmpty ?? false)
                            ? null
                            : 'Version requerida',
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: doorsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Cantidad de puertas'),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null) return 'Puertas requeridas';
                          if (n < 2 || n > 6) return 'Entre 2 y 6 puertas';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: plateController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'Patente'),
                        validator: (v) => (v?.trim().isNotEmpty ?? false)
                            ? null
                            : 'Patente requerida',
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: hasLicense,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Licencia de conducir vigente'),
                        subtitle: const Text(
                          'Obligatorio para conducir en TurnoApp.',
                        ),
                        onChanged: (v) => setModalState(() => hasLicense = v),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                if (!hasLicense) {
                                  AppSnackbar.show(
                                    context,
                                    'Debes declarar licencia vigente.',
                                    isError: true,
                                  );
                                  return;
                                }

                                setModalState(() => saving = true);
                                try {
                                  await ref
                                      .read(profileServiceProvider)
                                      .updateProfileDetails(
                                        fullName:
                                            fullNameController.text.trim(),
                                        profilePhotoUrl:
                                            profile.profilePhotoUrl,
                                        vehicleBrand:
                                            brandController.text.trim(),
                                        vehicleModel:
                                            modelController.text.trim(),
                                        vehicleVersion:
                                            versionController.text.trim(),
                                        vehicleDoors: int.parse(
                                            doorsController.text.trim()),
                                        vehiclePlate: plateController.text
                                            .trim()
                                            .toUpperCase()
                                            .replaceAll(' ', ''),
                                        vehicleColor: profile.vehicleColor,
                                        emergencyContact:
                                            profile.emergencyContact,
                                        safetyNotes: profile.safetyNotes,
                                        hasValidLicense: hasLicense,
                                      );

                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop(true);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    AppSnackbar.show(
                                      context,
                                      AppErrorMapper.toMessage(
                                        e,
                                        fallback:
                                            'No pudimos guardar los datos del vehiculo.',
                                      ),
                                      isError: true,
                                    );
                                  }
                                  setModalState(() => saving = false);
                                }
                              },
                        child: Text(
                            saving ? 'Guardando...' : 'Guardar y continuar'),
                      ),
                      TextButton(
                        onPressed:
                            saving ? null : () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    fullNameController.dispose();
    brandController.dispose();
    modelController.dispose();
    versionController.dispose();
    doorsController.dispose();
    plateController.dispose();

    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final profile = state.profile;
    final wallet = state.wallet;
    final isDriver = profile?.roleMode == RoleMode.driver;
    final notifState = ref.watch(inAppNotificationProvider);
    final unreadCount = notifState.unreadCount;

    if (!state.loading && !_fadeController.isCompleted) {
      _fadeController.forward();
    }

    final balanceStr = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(wallet?.balanceAvailable ?? 0);

    return LoadingOverlay(
      isLoading: state.switchingRole,
      message: 'Actualizando modo...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TurnoApp'),
          actions: [
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => context.push('/notifications'),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.danger,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              onPressed: () => context.push('/wallet'),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authServiceProvider).signOut();
              },
            ),
          ],
        ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
            : DecorativeBackground(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _RoleSwitchCard(
                          isDriver: isDriver,
                          name: profile?.fullName ?? 'Usuario',
                          photoUrl: profile?.profilePhotoUrl,
                          onToggle: _toggleRole,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final changed = await context.push('/profile/edit');
                            if (changed == true) {
                              _load();
                            }
                          },
                          icon: const Icon(Icons.person_outline),
                          label: const Text('Editar mi perfil y auto'),
                        ),
                        const SizedBox(height: 12),
                        _BalanceCard(
                          balance: balanceStr,
                          held: wallet?.balanceHeld ?? 0,
                          onTopup: () => context.push('/wallet'),
                        ),
                        if ((profile?.strikesCount ?? 0) > 0 ||
                            (profile?.suspendedUntil != null) ||
                            (profile?.vehicleSuspendedUntil != null)) ...[
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Estado de seguridad',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Strikes activas: ${profile?.strikesCount ?? 0}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (profile?.vehicleSuspendedUntil != null)
                                    Text(
                                      'Baneo vehiculo hasta: ${DateFormat('d MMM y', 'es').format(profile!.vehicleSuspendedUntil!)}',
                                      style: const TextStyle(
                                        color: AppTheme.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  if (profile?.suspendedUntil != null)
                                    Text(
                                      'Suspendido hasta: ${DateFormat('d MMM y', 'es').format(profile!.suspendedUntil!)}',
                                      style: const TextStyle(
                                        color: AppTheme.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          'Acciones principales',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        if (isDriver) ...[
                          _ActionButton(
                            icon: Icons.add_circle_outline,
                            label: 'Publicar turno',
                            subtitle: 'Comparte tu ruta y define cupos',
                            color: AppTheme.primary,
                            onTap: () => context.push('/publish'),
                          ),
                          const SizedBox(height: 10),
                          _ActionButton(
                            icon: Icons.directions_car_outlined,
                            label: 'Mis turnos publicados',
                            subtitle: 'Revisa pasajeros y estado de viajes',
                            color: const Color(0xFF1760A3),
                            onTap: () => context.push('/driver-rides'),
                          ),
                        ] else ...[
                          _ActionButton(
                            icon: Icons.search,
                            label: 'Buscar turno',
                            subtitle: 'Encuentra viajes por comuna y campus',
                            color: AppTheme.primary,
                            onTap: () => context.push('/search'),
                          ),
                          const SizedBox(height: 10),
                          _ActionButton(
                            icon: Icons.confirmation_num_outlined,
                            label: 'Mis reservas',
                            subtitle:
                                'Sigue el estado del viaje y revisa historial',
                            color: const Color(0xFF1760A3),
                            onTap: () => context.push('/my-rides'),
                          ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/terms'),
                          icon: const Icon(Icons.gavel_outlined),
                          label: const Text('Terminos y seguridad'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => context.push('/favorites'),
                                icon: const Icon(Icons.favorite_outline),
                                label: const Text('Favoritos'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => context.push('/privacy'),
                                icon: const Icon(Icons.privacy_tip_outlined),
                                label: const Text('Privacidad'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/support'),
                          icon: const Icon(Icons.support_agent_outlined),
                          label: const Text('Soporte'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            AppSnackbar.show(
                              context,
                              'En emergencia llama al ${AppConstants.emergencyPhoneCL}.',
                              isError: true,
                            );
                          },
                          icon: const Icon(Icons.emergency_outlined),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(color: AppTheme.danger),
                          ),
                          label: const Text('Boton de panico'),
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

class _RoleSwitchCard extends StatelessWidget {
  final bool isDriver;
  final String name;
  final String? photoUrl;
  final VoidCallback onToggle;

  const _RoleSwitchCard({
    required this.isDriver,
    required this.name,
    this.photoUrl,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final panel = const Color(0xFF0D1A2D);
    final border = const Color(0xFF1D3E66);
    final dim = const Color(0xFF9CB5D3);
    final highlight = const Color(0xFF73D9FF);
    return Card(
      color: panel,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
                      ? NetworkImage(photoUrl!)
                      : null,
                  child: (photoUrl == null || photoUrl!.isEmpty)
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isDriver ? 'Modo Conductor' : 'Modo Pasajero',
                        style: TextStyle(
                          color: isDriver
                              ? const Color(0xFF8BE6FF)
                              : const Color(0xFF49B9FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isDriver)
                        Text(
                          'Requiere licencia vigente y terminos aceptados',
                          style: TextStyle(
                            fontSize: 11,
                            color: dim,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (photoUrl == null || photoUrl!.isEmpty)
              Text(
                'Tip: agrega foto de perfil en editar perfil para generar mas confianza.',
                style: TextStyle(fontSize: 11, color: dim),
              ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1423),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_walk,
                    size: 18,
                    color: !isDriver ? const Color(0xFF49B9FF) : dim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isDriver ? 'Conductor' : 'Pasajero',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Switch(
                    value: isDriver,
                    onChanged: (_) => onToggle(),
                    activeColor: highlight,
                  ),
                  Icon(
                    Icons.drive_eta,
                    size: 18,
                    color: isDriver ? highlight : dim,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String balance;
  final int held;
  final VoidCallback onTopup;

  const _BalanceCard({
    required this.balance,
    required this.held,
    required this.onTopup,
  });

  @override
  Widget build(BuildContext context) {
    final heldStr = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(held);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF041227), Color(0xFF0E3A63), Color(0xFF1F8DE6)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x551073D6),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Saldo disponible',
            style: TextStyle(fontSize: 13, color: Color(0xFFD7E8F2)),
          ),
          const SizedBox(height: 2),
          Text(
            balance,
            style: const TextStyle(
              fontSize: 30,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (held > 0)
            Text(
              '$heldStr en reservas activas',
              style: const TextStyle(fontSize: 12, color: Color(0xFFD7E8F2)),
            ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onTopup,
            icon: const Icon(Icons.add),
            label: const Text('Recargar billetera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        splashColor: Colors.white.withValues(alpha: 0.2),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.92),
                color.withValues(alpha: 0.68),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0x3349B9FF)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFFE2EDF3),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
