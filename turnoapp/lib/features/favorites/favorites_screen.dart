import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../models/enums.dart';
import '../../providers/favorites_provider.dart';
import '../../services/favorites_service.dart';
import '../../services/report_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/decorative_background.dart';
import '../../shared/widgets/report_user_dialog.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  RoleMode? _filter;
  final _reportService = ReportService();
  final _favoritesService = FavoritesService();

  Future<void> _reload() {
    return ref.read(favoritesProvider.notifier).load(roleFilter: _filter);
  }

  void _showActionsSheet(
    BuildContext context,
    String userId,
    String userName,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                userName,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Eliminar de favoritos'),
                      content: Text('¿Quitar a $userName de tus favoritos?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Quitar'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    try {
                      await _favoritesService.toggleFavorite(userId);
                      _reload();
                      if (mounted) {
                        AppSnackbar.show(
                          context,
                          'Usuario eliminado de favoritos.',
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        AppSnackbar.show(
                          context,
                          'No se pudo quitar de favoritos. Intenta de nuevo.',
                          isError: true,
                        );
                      }
                      debugPrint('[Turno] Favorites: toggle failed: $e');
                    }
                  }
                },
                icon: const Icon(Icons.heart_broken_outlined),
                label: const Text('Quitar de favoritos'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  showDialog<bool>(
                    context: context,
                    builder: (_) => ReportUserDialog(
                      reportedUserId: userId,
                      reportedUserName: userName,
                    ),
                  );
                },
                icon: const Icon(Icons.flag_outlined),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.warning,
                  side: const BorderSide(color: AppTheme.warning),
                ),
                label: const Text('Reportar usuario'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Bloquear usuario'),
                      content: Text(
                          'Al bloquear a $userName, no podran interactuar entre si.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Bloquear'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    try {
                      await _reportService.blockUser(userId);
                      if (mounted) {
                        AppSnackbar.show(context, 'Usuario bloqueado.');
                        _reload();
                      }
                    } catch (e) {
                      if (mounted) {
                        AppSnackbar.show(
                          context,
                          'No pudimos bloquear al usuario.',
                          isError: true,
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.block_outlined),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                ),
                label: const Text('Bloquear usuario'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
      ),
      body: DecorativeBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Todos'),
                      selected: _filter == null,
                      onSelected: (_) {
                        setState(() => _filter = null);
                        _reload();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Conductores'),
                      selected: _filter == RoleMode.driver,
                      onSelected: (_) {
                        setState(() => _filter = RoleMode.driver);
                        _reload();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Pasajeros'),
                      selected: _filter == RoleMode.passenger,
                      onSelected: (_) {
                        setState(() => _filter = RoleMode.passenger);
                        _reload();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.favorites.isEmpty
                      ? const _EmptyState()
                      : RefreshIndicator(
                          onRefresh: _reload,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                            itemCount: state.favorites.length,
                            itemBuilder: (context, index) {
                              final item = state.favorites[index];
                              final isDriver = item.roleMode == RoleMode.driver;
                              return Card(
                                child: ListTile(
                                  onLongPress: () =>
                                      _showActionsSheet(
                                        context,
                                        item.userId,
                                        item.fullName ?? 'Usuario',
                                      ),
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    backgroundImage: (item.profilePhotoUrl !=
                                                null &&
                                            item.profilePhotoUrl!.isNotEmpty)
                                        ? NetworkImage(item.profilePhotoUrl!)
                                        : null,
                                    child: (item.profilePhotoUrl == null ||
                                            item.profilePhotoUrl!.isEmpty)
                                        ? Text(
                                            _initial(item.fullName),
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    item.fullName ?? 'Usuario',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isDriver ? 'Conductor' : 'Pasajero',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.subtle,
                                        ),
                                      ),
                                      Text(
                                        'Rating ${item.ratingAvg.toStringAsFixed(2)} (${item.ratingCount})',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.subtle,
                                        ),
                                      ),
                                      if ((item.vehicleModel ?? '')
                                              .isNotEmpty ||
                                          (item.vehiclePlate ?? '').isNotEmpty)
                                        Text(
                                          'Auto ${item.vehicleModel ?? '-'} · Patente ${item.vehiclePlate ?? '-'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.subtle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: const Icon(
                                    Icons.favorite,
                                    color: Color(0xFFFF5A7A),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

String _initial(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return '?';
  return raw.substring(0, 1).toUpperCase();
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          'Aun no agregas usuarios a favoritos.\nDesde detalle de turno o reservas puedes guardarlos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.subtle),
        ),
      ),
    );
  }
}
