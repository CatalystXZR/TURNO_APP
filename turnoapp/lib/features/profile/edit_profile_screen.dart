import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../services/profile_service.dart';
import '../../services/wallet_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/loading_overlay.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = ProfileService();
  final _walletService = WalletService();
  final _picker = ImagePicker();

  final _fullNameController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleBrandController = TextEditingController();
  final _vehicleVersionController = TextEditingController();
  final _vehicleDoorsController = TextEditingController();
  final _vehiclePlateController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _safetyNotesController = TextEditingController();

  bool _hasValidLicense = false;
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;

  String? _existingPhotoUrl;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _vehicleModelController.dispose();
    _vehicleBrandController.dispose();
    _vehicleVersionController.dispose();
    _vehicleDoorsController.dispose();
    _vehiclePlateController.dispose();
    _vehicleColorController.dispose();
    _emergencyContactController.dispose();
    _safetyNotesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await _profileService.getProfile();
      if (profile == null) {
        throw Exception('profile_not_found');
      }

      _fullNameController.text = profile.fullName ?? '';
      _existingPhotoUrl = profile.profilePhotoUrl;
      _vehicleBrandController.text = profile.vehicleBrand ?? '';
      _vehicleModelController.text = profile.vehicleModel ?? '';
      _vehicleVersionController.text = profile.vehicleVersion ?? '';
      _vehicleDoorsController.text =
          profile.vehicleDoors != null ? '${profile.vehicleDoors}' : '';
      _vehiclePlateController.text = profile.vehiclePlate ?? '';
      _vehicleColorController.text = profile.vehicleColor ?? '';
      _emergencyContactController.text = profile.emergencyContact ?? '';
      _safetyNotesController.text = profile.safetyNotes ?? '';
      _hasValidLicense = profile.hasValidLicense;
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos cargar tu perfil.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      var photoUrlToSave = _existingPhotoUrl;
      if (_selectedPhotoBytes != null) {
        photoUrlToSave = await _profileService.uploadProfilePhoto(
          bytes: _selectedPhotoBytes!,
          fileName: _selectedPhotoName ?? 'avatar.jpg',
        );
      }

      await _profileService.updateProfileDetails(
        fullName: _fullNameController.text.trim(),
        profilePhotoUrl: photoUrlToSave,
        vehicleBrand: _nullIfEmpty(_vehicleBrandController.text),
        vehicleModel: _nullIfEmpty(_vehicleModelController.text),
        vehicleVersion: _nullIfEmpty(_vehicleVersionController.text),
        vehicleDoors: int.tryParse(_vehicleDoorsController.text.trim()),
        vehiclePlate: _normalizePlate(_vehiclePlateController.text),
        vehicleColor: _nullIfEmpty(_vehicleColorController.text),
        emergencyContact: _nullIfEmpty(_emergencyContactController.text),
        safetyNotes: _nullIfEmpty(_safetyNotesController.text),
        hasValidLicense: _hasValidLicense,
      );

      _existingPhotoUrl = photoUrlToSave;
      _selectedPhotoBytes = null;
      _selectedPhotoName = null;

      if (mounted) {
        AppSnackbar.show(context, 'Perfil actualizado correctamente');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos guardar tu perfil. Intenta nuevamente.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizePlate(String value) {
    final trimmed = value.trim().toUpperCase().replaceAll(' ', '');
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() {
        _selectedPhotoBytes = bytes;
        _selectedPhotoName = picked.name;
      });

      AppSnackbar.show(context, 'Foto seleccionada. Guarda para subirla.');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos abrir la camara o galeria.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _showPhotoPickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Seleccionar foto',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickPhoto(ImageSource.camera);
                  },
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Tomar foto'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickPhoto(ImageSource.gallery);
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Elegir de galeria'),
                ),
                if (_selectedPhotoBytes != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _selectedPhotoBytes = null;
                        _selectedPhotoName = null;
                      });
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Quitar foto seleccionada'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewPhoto = _existingPhotoUrl?.trim() ?? '';
    ImageProvider<Object>? avatarProvider;
    if (_selectedPhotoBytes != null) {
      avatarProvider = MemoryImage(_selectedPhotoBytes!);
    } else if (previewPhoto.isNotEmpty) {
      avatarProvider = NetworkImage(previewPhoto);
    }

    return LoadingOverlay(
      isLoading: _saving || _deleting,
      message: _deleting ? 'Eliminando cuenta...' : 'Guardando perfil...',
      child: Scaffold(
        appBar: AppBar(title: const Text('Editar perfil')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: const Color(0xFFE7F0F6),
                              backgroundImage: avatarProvider,
                              child: (_selectedPhotoBytes == null &&
                                      previewPhoto.isEmpty)
                                  ? const Icon(Icons.person_outline, size: 32)
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: _showPhotoPickerSheet,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: const Text('Cargar foto'),
                            ),
                            if (_selectedPhotoName != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _selectedPhotoName!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.subtle,
                                ),
                              ),
                            ],
                            if (_selectedPhotoBytes != null) ...[
                              const SizedBox(height: 6),
                              const Text(
                                'La foto se subira al guardar cambios.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.danger,
                                ),
                              ),
                            ],
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
                            TextFormField(
                              controller: _fullNameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nombre completo',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) => (v?.trim().length ?? 0) >= 3
                                  ? null
                                  : 'Requerido',
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emergencyContactController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Contacto emergencia (opcional)',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _safetyNotesController,
                              decoration: const InputDecoration(
                                labelText: 'Notas de seguridad (opcional)',
                                prefixIcon: Icon(Icons.shield_outlined),
                              ),
                              maxLines: 3,
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
                          children: [
                            Text(
                              'Datos del auto',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _vehicleBrandController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Marca (opcional)',
                                prefixIcon: Icon(Icons.directions_car_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _vehicleModelController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Auto / modelo (opcional)',
                                prefixIcon: Icon(Icons.directions_car_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _vehicleVersionController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Version (opcional)',
                                prefixIcon: Icon(Icons.tune_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _vehicleDoorsController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Cantidad de puertas (opcional)',
                                prefixIcon:
                                    Icon(Icons.door_front_door_outlined),
                              ),
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) return null;
                                final n = int.tryParse(value);
                                if (n == null)
                                  return 'Ingresa un numero valido';
                                if (n < 2 || n > 6)
                                  return 'Entre 2 y 6 puertas';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _vehiclePlateController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Patente (opcional)',
                                prefixIcon:
                                    Icon(Icons.confirmation_number_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _vehicleColorController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Color del auto (opcional)',
                                prefixIcon: Icon(Icons.palette_outlined),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Licencia de conducir vigente'),
                              subtitle: const Text(
                                'Necesaria para activar modo conductor.',
                              ),
                              value: _hasValidLicense,
                              onChanged: (v) =>
                                  setState(() => _hasValidLicense = v),
                            ),
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
                            Text(
                              'Privacidad y cuenta',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Puedes solicitar la eliminacion completa de tu cuenta y datos personales desde aqui.',
                              style: TextStyle(
                                color: AppTheme.subtle,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed:
                                  _deleting ? null : _confirmDeleteAccount,
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
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar cambios'),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta accion eliminara tu cuenta y datos asociados de Turno.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                hintText: 'Ej: deje de usar la app',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    final reason = reasonController.text.trim();
    setState(() => _deleting = true);
    try {
      await _walletService.deleteUserAccount(
        reason: reason.isNotEmpty ? reason : null,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Tu cuenta fue eliminada correctamente.',
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos eliminar tu cuenta en este momento.',
        ),
        isError: true,
      );
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _deleting = false);
    }
  }
}
