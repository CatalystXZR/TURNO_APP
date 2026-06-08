/**
 * Project: Turno
 * 
 * Project Owners: Cristobal Cordova, Carlos Ibarra, Agustin Puelma
 * Software Architecture & Code: Matias Toledo (@catalystxzr)
 * 
 * Description: Production-grade implementation for UDD carpooling system.
 * 
 * Copyright (c) 2026 Turno. All rights reserved.
 * This software is proprietary and confidential.
 */

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../models/user_profile.dart';
import '../../models/ride.dart';
import '../../models/enums.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/reference_data_service.dart';
import '../../services/ride_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/loading_overlay.dart';

class PublishRideScreen extends StatefulWidget {
  const PublishRideScreen({super.key});

  @override
  State<PublishRideScreen> createState() => _PublishRideScreenState();
}

class _PublishRideScreenState extends State<PublishRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rideService = RideService();
  final _authService = AuthService();
  final _profileService = ProfileService();
  final _referenceDataService = ReferenceDataService();

  String? _selectedCommune;
  String? _selectedUniversityId;
  String? _selectedUniversityCode;
  String? _selectedCampusId;
  final _meetingPointController = TextEditingController();
  bool _isRadial = false;
  RideDirection _direction = RideDirection.toCampus;
  DateTime? _departureAt;
  int _seats = 3;
  bool _loading = false;

  // Fetched from DB
  List<Map<String, dynamic>> _universities = [];
  List<Map<String, dynamic>> _campuses = [];
  bool _loadingUniversities = true;
  bool _loadingCampuses = false;
  String? _referenceError;
  UserProfile? _profile;

  @override
  void dispose() {
    _meetingPointController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadUniversities();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      if (mounted) {
        setState(() => _profile = profile);
      }
    } catch (_) {
      // Non-blocking; checked on submit too.
    }
  }

  Future<void> _loadUniversities() async {
    if (mounted) {
      setState(() {
        _loadingUniversities = true;
        _referenceError = null;
      });
    }

    try {
      final rows = await _referenceDataService.getUniversities();
      if (mounted) {
        setState(() {
          _universities = rows;
          _referenceError = _referenceDataService.lastCallUsedFallback
              ? 'No se pudo cargar desde Supabase. Se usan datos de referencia locales.'
              : null;
          _loadingUniversities = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUniversities = false;
          _referenceError = AppErrorMapper.toMessage(e,
              fallback: 'No pudimos cargar universidades.');
        });
      }
    }
  }

  Future<void> _loadCampuses(String universityId) async {
    if (mounted) {
      setState(() {
        _loadingCampuses = true;
        _referenceError = null;
      });
    }
    try {
      final rows =
          await _referenceDataService.getCampusesByUniversity(universityId);
      if (mounted) {
        setState(() {
          _campuses = rows;
          if (_referenceDataService.lastCallUsedFallback) {
            _referenceError =
                'No se pudo cargar desde Supabase. Se usan datos de referencia locales.';
          }
          _selectedCampusId = null;
          _loadingCampuses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCampuses = false;
          _referenceError = AppErrorMapper.toMessage(e,
              fallback: 'No pudimos cargar campus.');
        });
      }
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;

    setState(() {
      _departureAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_departureAt == null) {
      AppSnackbar.show(context, 'Selecciona fecha y hora', isError: true);
      return;
    }
    if (_selectedCampusId == null || _selectedUniversityId == null) {
      AppSnackbar.show(context, 'Selecciona universidad y campus',
          isError: true);
      return;
    }
    if (_meetingPointController.text.trim().length < 4) {
      AppSnackbar.show(context, 'Define un punto de encuentro claro.',
          isError: true);
      return;
    }

    if (!_departureAt!.isAfter(DateTime.now())) {
      AppSnackbar.show(
        context,
        'La hora del turno debe ser futura.',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);
    try {
      if (!(_profile?.acceptedTerms ?? false)) {
        throw Exception('terms_not_accepted');
      }
      if (!(_profile?.hasValidLicense ?? false)) {
        throw Exception('driver_license_required');
      }

      final uid = _authService.currentUserId;
      if (uid == null) {
        throw Exception('unauthorized');
      }

      final uni =
          await _referenceDataService.getUniversityById(_selectedUniversityId!);
      final universityCode =
          _selectedUniversityCode ?? (uni?['code'] as String?) ?? 'UDD';
      final seatPrice = AppConstants.seatPriceForUniversityCode(universityCode);
      final fee = AppConstants.platformFeeForAmount(
        seatPrice,
        isRadial: _isRadial,
      );
      final net = seatPrice - fee;

      final ride = Ride(
        id: '',
        driverId: uid,
        universityId: _selectedUniversityId!,
        universityCode: universityCode,
        campusId: _selectedCampusId!,
        originCommune: _selectedCommune!,
        meetingPoint: _meetingPointController.text.trim(),
        isRadial: _isRadial,
        direction: _direction,
        departureAt: _departureAt!,
        seatPrice: seatPrice,
        platformFee: fee,
        driverNetAmount: net,
        seatsTotal: _seats,
        seatsAvailable: _seats,
        status: 'active',
        createdAt: DateTime.now(),
      );
      await _rideService.createRide(ride);
      if (mounted) {
        AppSnackbar.show(context, 'Turno publicado correctamente');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos publicar el turno. Intenta nuevamente.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departureFmt = _departureAt != null
        ? DateFormat('EEE d MMM, HH:mm', 'es').format(_departureAt!)
        : 'Seleccionar';
    final directionLabel =
        _direction == RideDirection.toCampus ? 'Hacia campus' : 'Desde campus';
    final seatPricePreview =
        AppConstants.seatPriceForUniversityCode(_selectedUniversityCode);
    final feePreview = AppConstants.platformFeeForAmount(
      seatPricePreview,
      isRadial: _isRadial,
    );
    final netPreview = seatPricePreview - feePreview;

    return LoadingOverlay(
      isLoading: _loading,
      child: Scaffold(
        appBar: AppBar(title: const Text('Publicar turno')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 108),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF041227),
                      Color(0xFF0E3A63),
                      Color(0xFF1F8DE6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x551073D6),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _direction == RideDirection.toCampus
                            ? Icons.north_east_rounded
                            : Icons.south_west_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nuevo turno',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$directionLabel - ${_seats.toString()} cupos',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFFD7E8F2)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direccion del viaje',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<RideDirection>(
                        segments: const [
                          ButtonSegment(
                            value: RideDirection.toCampus,
                            label: Text('Hacia campus'),
                            icon: Icon(Icons.school_outlined),
                          ),
                          ButtonSegment(
                            value: RideDirection.fromCampus,
                            label: Text('Desde campus'),
                            icon: Icon(Icons.home_outlined),
                          ),
                        ],
                        selected: {_direction},
                        onSelectionChanged: (s) =>
                            setState(() => _direction = s.first),
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
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCommune,
                        decoration: const InputDecoration(
                          labelText: 'Comuna de origen',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        items: AppConstants.allowedCommunes
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedCommune = v;
                            if (v != 'Chicureo') {
                              _isRadial = false;
                            }
                          });
                        },
                        validator: (v) => v != null ? null : 'Requerido',
                      ),
                      const SizedBox(height: 12),
                      _loadingUniversities
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: LinearProgressIndicator(minHeight: 3),
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: _selectedUniversityId,
                              decoration: const InputDecoration(
                                labelText: 'Universidad',
                                prefixIcon: Icon(Icons.school_outlined),
                              ),
                              items: _universities
                                  .map(
                                    (u) => DropdownMenuItem<String>(
                                      value: u['id'] as String,
                                      child: Text(u['name'] as String),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setState(() {
                                  _selectedUniversityId = v;
                                  final selected = _universities
                                      .where((u) => u['id'] == v)
                                      .cast<Map<String, dynamic>>()
                                      .toList();
                                  _selectedUniversityCode = selected.isNotEmpty
                                      ? selected.first['code'] as String?
                                      : null;
                                  _selectedCampusId = null;
                                  _campuses = [];
                                });
                                if (v != null) _loadCampuses(v);
                              },
                              validator: (v) => v != null ? null : 'Requerido',
                            ),
                      const SizedBox(height: 12),
                      _loadingCampuses
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: LinearProgressIndicator(minHeight: 3),
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: _selectedCampusId,
                              decoration: const InputDecoration(
                                labelText: 'Campus',
                                prefixIcon: Icon(Icons.place_outlined),
                              ),
                              items: _campuses
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c['id'] as String,
                                      child: Text(c['name'] as String),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedCampusId = v),
                              validator: (v) => v != null ? null : 'Requerido',
                            ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _meetingPointController,
                        decoration: const InputDecoration(
                          labelText: 'Punto de encuentro',
                          prefixIcon: Icon(Icons.pin_drop_outlined),
                        ),
                        validator: (v) => (v?.trim().length ?? 0) >= 4
                            ? null
                            : 'Define un punto de encuentro',
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ruta radial'),
                        subtitle: Text(
                          _selectedCommune != 'Chicureo'
                              ? 'Solo disponible para Chicureo'
                              : 'Extension de ruta desde Chicureo',
                        ),
                        value: _isRadial,
                        onChanged: _selectedCommune == 'Chicureo'
                            ? (v) => setState(() => _isRadial = v)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              if (_referenceError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEACCD3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _referenceError!,
                          style: const TextStyle(color: AppTheme.danger),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadUniversities,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: const Text('Fecha y hora de salida'),
                        subtitle: Text(departureFmt),
                        trailing: TextButton(
                          onPressed: _pickDateTime,
                          child: const Text('Cambiar'),
                        ),
                      ),
                      const Divider(height: 18),
                      Row(
                        children: [
                          Text(
                            'Cupos disponibles',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _seats > 1
                                ? () => setState(() => _seats--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$_seats',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          IconButton(
                            onPressed: _seats < 6
                                ? () => setState(() => _seats++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Precio por asiento: \$$seatPricePreview',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Comision pasajero: \$$feePreview · Conductor recibe: \$$netPreview',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.subtle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'La comision se cobra al pasajero; el conductor no tiene cobro adicional.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.subtle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _submit,
            icon: const Icon(Icons.publish_outlined),
            label: const Text('Publicar turno'),
          ),
        ),
      ),
    );
  }
}
