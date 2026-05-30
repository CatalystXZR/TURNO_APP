/**
 *
 * Project: Turno
 *
 * Original Concept: Agustín Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matías Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/reference_data_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/loading_overlay.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _vehicleBrandController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleVersionController = TextEditingController();
  final _vehicleDoorsController = TextEditingController();
  final _vehiclePlateController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _acceptedTerms = false;
  bool _hasValidLicense = false;
  bool _registerAsDriver = false;

  // Universities loaded from DB so we work with real UUIDs
  List<Map<String, dynamic>> _universities = [];
  String? _selectedUniversityId;
  bool _loadingUniversities = true;
  String? _universitiesError;

  final _auth = AuthService();
  final _profileService = ProfileService();
  final _referenceDataService = ReferenceDataService();

  @override
  void initState() {
    super.initState();
    _loadUniversities();
  }

  Future<void> _loadUniversities() async {
    if (mounted) {
      setState(() {
        _loadingUniversities = true;
        _universitiesError = null;
      });
    }
    try {
      final rows = await _referenceDataService.getUniversities();
      if (mounted) {
        setState(() {
          _universities = rows;
          _universitiesError = _referenceDataService.lastCallUsedFallback
              ? 'No se pudo cargar desde Supabase. Se usan datos de referencia locales.'
              : null;
          _loadingUniversities = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUniversities = false;
          _universities = [];
          _universitiesError = AppErrorMapper.toMessage(
            e,
            fallback: 'No se pudo cargar la lista de universidades.',
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _vehicleBrandController.dispose();
    _vehicleModelController.dispose();
    _vehicleVersionController.dispose();
    _vehicleDoorsController.dispose();
    _vehiclePlateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final authResponse = await _auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        acceptedTerms: _acceptedTerms,
        termsVersion: AppConstants.termsVersion,
        hasValidLicense: _hasValidLicense,
        roleMode: _registerAsDriver ? 'driver' : 'passenger',
        vehicleBrand:
            _registerAsDriver ? _vehicleBrandController.text.trim() : null,
        vehicleModel:
            _registerAsDriver ? _vehicleModelController.text.trim() : null,
        vehicleVersion:
            _registerAsDriver ? _vehicleVersionController.text.trim() : null,
        vehicleDoors: _registerAsDriver
            ? int.tryParse(_vehicleDoorsController.text.trim())
            : null,
        vehiclePlate:
            _registerAsDriver ? _vehiclePlateController.text.trim() : null,
      );

      final uid = _auth.currentUserId;

      // Best-effort profile completion: account creation should not fail here.
      if (uid != null && _selectedUniversityId != null) {
        try {
          await _profileService.saveBasicProfile(
            userId: uid,
            fullName: _nameController.text.trim(),
            universityId: _selectedUniversityId,
            acceptedTerms: _acceptedTerms,
            termsVersion: AppConstants.termsVersion,
            hasValidLicense: _hasValidLicense,
            roleMode: _registerAsDriver ? 'driver' : 'passenger',
            vehicleBrand:
                _registerAsDriver ? _vehicleBrandController.text.trim() : null,
            vehicleModel:
                _registerAsDriver ? _vehicleModelController.text.trim() : null,
            vehicleVersion: _registerAsDriver
                ? _vehicleVersionController.text.trim()
                : null,
            vehicleDoors: _registerAsDriver
                ? int.tryParse(_vehicleDoorsController.text.trim())
                : null,
            vehiclePlate:
                _registerAsDriver ? _vehiclePlateController.text.trim() : null,
          );
        } catch (e) {
          debugPrint('[Turno] Register: profile save failed (best-effort): $e');
        }
      }

      if (!mounted) return;

      if (authResponse.session == null) {
        AppSnackbar.show(
          context,
          'Cuenta creada. Revisa tu correo para confirmar y luego inicia sesion.',
        );
        context.go('/login');
      } else {
        AppSnackbar.show(context, 'Cuenta creada correctamente');
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos crear tu cuenta. Intenta nuevamente.',
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
    return LoadingOverlay(
      isLoading: _loading,
      child: Scaffold(
        appBar: AppBar(title: const Text('Crear cuenta')),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF040B18), Color(0xFF0A1A31), Color(0xFF0D2848)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Bienvenido a Turno',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Crea tu cuenta para publicar o reservar turnos.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.subtle),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Nombre completo',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => v != null && v.trim().length > 2
                                ? null
                                : 'Requerido',
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Correo universitario',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) => v != null && v.contains('@')
                                ? null
                                : 'Correo invalido',
                          ),
                          const SizedBox(height: 14),
                          _loadingUniversities
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_universitiesError != null) ...[
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: const Color(0xFFE6C5CB),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          color: const Color(0xFFFDF4F6),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.info_outline,
                                              color: Color(0xFF8A2F43),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _universitiesError!,
                                                style: const TextStyle(
                                                  color: Color(0xFF8A2F43),
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: _loadUniversities,
                                              child: const Text('Reintentar'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    if (_universities.isEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFFE6C5CB),
                                          ),
                                          color: const Color(0xFFFDF4F6),
                                        ),
                                        child: const Text(
                                          'No hay universidades disponibles. Revisa tu conexion o permisos en Supabase (migraciones 06 y 07).',
                                          style: TextStyle(
                                              color: Color(0xFF8A2F43)),
                                        ),
                                      )
                                    else
                                      DropdownButtonFormField<String>(
                                        initialValue: _selectedUniversityId,
                                        decoration: const InputDecoration(
                                          labelText: 'Universidad',
                                          prefixIcon:
                                              Icon(Icons.school_outlined),
                                        ),
                                        items: _universities
                                            .map(
                                              (u) => DropdownMenuItem<String>(
                                                value: u['id'] as String,
                                                child:
                                                    Text(u['name'] as String),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setState(
                                            () => _selectedUniversityId = v),
                                        validator: (v) {
                                          if (_universities.isEmpty)
                                            return null;
                                          return v != null
                                              ? null
                                              : 'Selecciona tu universidad';
                                        },
                                      ),
                                  ],
                                ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscure,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Contrasena',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => v != null && v.length >= 6
                                ? null
                                : 'Minimo 6 caracteres',
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title:
                                const Text('Quiero registrarme como conductor'),
                            subtitle: const Text(
                              'Si lo activas, debes ingresar datos del vehiculo.',
                            ),
                            value: _registerAsDriver,
                            onChanged: (v) =>
                                setState(() => _registerAsDriver = v),
                          ),
                          if (_registerAsDriver) ...[
                            const SizedBox(height: 10),
                            Card(
                              color: const Color(0xFFF8FBFD),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _vehicleBrandController,
                                      decoration: const InputDecoration(
                                        labelText: 'Marca',
                                        prefixIcon:
                                            Icon(Icons.directions_car_outlined),
                                      ),
                                      validator: (v) => _registerAsDriver
                                          ? ((v?.trim().isNotEmpty ?? false)
                                              ? null
                                              : 'Marca requerida')
                                          : null,
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _vehicleModelController,
                                      decoration: const InputDecoration(
                                        labelText: 'Modelo',
                                        prefixIcon:
                                            Icon(Icons.directions_car_outlined),
                                      ),
                                      validator: (v) => _registerAsDriver
                                          ? ((v?.trim().isNotEmpty ?? false)
                                              ? null
                                              : 'Modelo requerido')
                                          : null,
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _vehicleVersionController,
                                      decoration: const InputDecoration(
                                        labelText: 'Version',
                                        prefixIcon: Icon(Icons.tune_outlined),
                                      ),
                                      validator: (v) => _registerAsDriver
                                          ? ((v?.trim().isNotEmpty ?? false)
                                              ? null
                                              : 'Version requerida')
                                          : null,
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _vehicleDoorsController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Cantidad de puertas',
                                        prefixIcon: Icon(
                                            Icons.door_front_door_outlined),
                                      ),
                                      validator: (v) {
                                        if (!_registerAsDriver) return null;
                                        final n = int.tryParse(v?.trim() ?? '');
                                        if (n == null)
                                          return 'Puertas requeridas';
                                        if (n < 2 || n > 6)
                                          return 'Entre 2 y 6 puertas';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _vehiclePlateController,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      decoration: const InputDecoration(
                                        labelText: 'Patente',
                                        prefixIcon: Icon(
                                            Icons.confirmation_number_outlined),
                                      ),
                                      validator: (v) => _registerAsDriver
                                          ? ((v?.trim().isNotEmpty ?? false)
                                              ? null
                                              : 'Patente requerida')
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFD9E3EB)),
                              color: const Color(0xFFF8FBFD),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CheckboxListTile(
                                  value: _acceptedTerms,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: const Text(
                                    'Acepto terminos y condiciones, politica de tolerancia cero y reglas de strikes.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  onChanged: (v) => setState(
                                      () => _acceptedTerms = v ?? false),
                                ),
                                const SizedBox(height: 2),
                                CheckboxListTile(
                                  value: _hasValidLicense,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: const Text(
                                    'Declaro licencia de conducir vigente para activar modo conductor.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  onChanged: (v) => setState(
                                      () => _hasValidLicense = v ?? false),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 0,
                                    children: [
                                      TextButton(
                                        onPressed: () => context.push('/terms'),
                                        child: const Text('Terminos'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            context.push('/privacy'),
                                        child: const Text('Privacidad'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            context.push('/support'),
                                        child: const Text('Soporte'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton(
                            onPressed: (_loadingUniversities ||
                                    _universities.isEmpty ||
                                    !_acceptedTerms)
                                ? null
                                : _submit,
                            child: const Text('Crear cuenta'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => context.pop(),
                            child:
                                const Text('Ya tienes cuenta? Inicia sesion'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
