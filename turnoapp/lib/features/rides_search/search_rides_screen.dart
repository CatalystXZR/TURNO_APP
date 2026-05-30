/**
 *
 * Project: Turno
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

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../models/enums.dart';
import '../../providers/search_rides_provider.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/decorative_background.dart';
import '../../shared/widgets/turno_card.dart';

class SearchRidesScreen extends ConsumerStatefulWidget {
  const SearchRidesScreen({super.key});

  @override
  ConsumerState<SearchRidesScreen> createState() => _SearchRidesScreenState();
}

class _SearchRidesScreenState extends ConsumerState<SearchRidesScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _listController;
  late final Animation<double> _listAnimation;

  @override
  void initState() {
    super.initState();
    _listController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _listAnimation = CurvedAnimation(
      parent: _listController,
      curve: Curves.easeOut,
    );
    Future.microtask(
        () => ref.read(searchRidesProvider.notifier).loadCampuses());
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    try {
      await ref.read(searchRidesProvider.notifier).search();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos buscar turnos ahora. Intenta nuevamente.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (picked == null) return;
    ref.read(searchRidesProvider.notifier).setDate(picked);
    await _search();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchRidesProvider);
    final notifier = ref.read(searchRidesProvider.notifier);

    final hasAnyFilter = state.selectedCommune != null ||
        state.selectedDirection != null ||
        state.selectedCampusId != null ||
        state.selectedDate != null;

    if (!state.loading &&
        state.results.isNotEmpty &&
        !_listController.isCompleted) {
      _listController.forward();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar turnos'),
        actions: [
          if (state.searched || hasAnyFilter)
            TextButton(
              onPressed: notifier.clearFilters,
              child: const Text('Limpiar'),
            ),
        ],
      ),
      body: DecorativeBackground(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filtros rapidos',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChipDropdown<String>(
                        label: 'Comuna',
                        value: state.selectedCommune,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Sin filtro')),
                          ...AppConstants.allowedCommunes
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                        ],
                        onChanged: (v) async {
                          notifier.setCommune(v);
                          await _search();
                        },
                      ),
                      _FilterChipDropdown<String>(
                        label: 'Direccion',
                        value: state.selectedDirection,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Sin filtro')),
                          const DropdownMenuItem(
                              value: 'to_campus', child: Text('Hacia campus')),
                          const DropdownMenuItem(
                            value: 'from_campus',
                            child: Text('Desde campus'),
                          ),
                        ],
                        onChanged: (v) async {
                          notifier.setDirection(v);
                          await _search();
                        },
                      ),
                      state.campusesError != null
                          ? ActionChip(
                              avatar: const Icon(
                                Icons.error_outline,
                                size: 16,
                                color: AppTheme.danger,
                              ),
                              label: const Text('Reintentar campus'),
                              onPressed: notifier.loadCampuses,
                            )
                          : _FilterChipDropdown<String>(
                              label: state.loadingCampuses
                                  ? 'Cargando campus...'
                                  : 'Campus',
                              value: state.selectedCampusId,
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('Sin filtro')),
                                ...state.campuses
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c['id'] as String,
                                        child: Text(
                                          '${c['name']} · ${(c['universities'] as Map?)?['name'] ?? ''}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ],
                              onChanged: state.loadingCampuses
                                  ? (_) {}
                                  : (v) async {
                                      notifier.setCampus(v);
                                      await _search();
                                    },
                            ),
                      ActionChip(
                        label: Text(
                          state.selectedDate != null
                              ? '${state.selectedDate!.day}/${state.selectedDate!.month}'
                              : 'Fecha',
                        ),
                        avatar: const Icon(Icons.calendar_today, size: 16),
                        onPressed: _pickDate,
                        backgroundColor: state.selectedDate != null
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : !state.searched
                      ? _EmptyState(onSearch: _search)
                      : state.results.isEmpty
                          ? const _NoResults()
                          : FadeTransition(
                              opacity: _listAnimation,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.only(top: 2, bottom: 90),
                                itemCount: state.results.length,
                                itemBuilder: (context, i) {
                                  final ride = state.results[i];
                                  return TurnoCard(
                                    originCommune: ride.originCommune,
                                    universityName: ride.universityName ?? '',
                                    universityCode: ride.universityCode,
                                    campusName: ride.campusName ?? '',
                                    meetingPoint: ride.meetingPoint,
                                    departureAt: ride.departureAt,
                                    direction:
                                        ride.direction == RideDirection.toCampus
                                            ? 'to_campus'
                                            : 'from_campus',
                                    driverName: ride.driverName,
                                    driverRating: ride.driverRating,
                                    driverRatingCount: ride.driverRatingCount,
                                    seatsAvailable: ride.seatsAvailable,
                                    seatPrice: ride.seatPrice,
                                    platformFee: ride.platformFee,
                                    driverNetAmount: ride.driverNetAmount,
                                    isRadial: ride.isRadial,
                                    onTap: () =>
                                        context.push('/booking/${ride.id}'),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: !state.searched
          ? FloatingActionButton.extended(
              onPressed: _search,
              icon: const Icon(Icons.search),
              label: const Text('Buscar ahora'),
            )
          : null,
    );
  }
}

class _FilterChipDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FilterChipDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  String get _displayLabel {
    if (value == null) return label;
    final match = items.where((i) => i.value == value).firstOrNull;
    if (match == null) return label;
    final child = match.child;
    if (child is Text) return child.data ?? label;
    return label;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: (v) => onChanged(v),
      itemBuilder: (_) => items
          .map((item) => PopupMenuItem(value: item.value, child: item.child))
          .toList(),
      child: Chip(
        label: Text(_displayLabel),
        avatar: value != null
            ? const Icon(Icons.check_circle, size: 16, color: AppTheme.primary)
            : null,
        backgroundColor: value != null
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onSearch;

  const _EmptyState({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text(
            'Filtra o presiona buscar\npara ver turnos disponibles',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.subtle),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search),
            label: const Text('Buscar turnos'),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 64,
            color: AppTheme.subtle,
          ),
          SizedBox(height: 12),
          Text(
            'No hay turnos disponibles\ncon estos filtros',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.subtle),
          ),
        ],
      ),
    );
  }
}
