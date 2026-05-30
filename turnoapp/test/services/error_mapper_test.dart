import 'package:flutter_test/flutter_test.dart';
import 'package:turnoapp/core/error_mapper.dart';

void main() {
  group('AppErrorMapper.toMessage', () {
    test('returns fallback for unrecognized error', () {
      final msg = AppErrorMapper.toMessage('something unknown',
          fallback: 'Custom fallback');
      expect(msg, 'Custom fallback');
    });

    test('maps session errors', () {
      expect(AppErrorMapper.toMessage('JWT expired'), contains('Sesion'));
      expect(AppErrorMapper.toMessage('P0001'), contains('Sesion'));
    });

    test('maps network errors', () {
      expect(AppErrorMapper.toMessage('SocketException'), contains('conexion'));
    });

    test('maps invalid credentials', () {
      expect(AppErrorMapper.toMessage('Invalid login credentials'),
          contains('incorrectos'));
    });

    test('maps already registered', () {
      expect(AppErrorMapper.toMessage('User already registered'),
          contains('ya tiene una cuenta'));
    });

    test('maps insufficient balance', () {
      expect(AppErrorMapper.toMessage('P0004: insufficient'),
          contains('Saldo insuficiente'));
    });

    test('maps ride unavailable', () {
      expect(AppErrorMapper.toMessage('P0002: ride unavailable'),
          contains('no esta disponible'));
    });

    test('maps already booked', () {
      expect(AppErrorMapper.toMessage('P0003: already booked'),
          contains('Ya tienes una reserva'));
    });

    test('maps forbidden', () {
      expect(AppErrorMapper.toMessage('P0006: forbidden'),
          contains('No tienes permisos'));
    });

    test('maps ride departed', () {
      expect(AppErrorMapper.toMessage('P0010: ride_departed'),
          contains('ya inicio'));
    });

    test('maps invalid dispatch transition', () {
      expect(AppErrorMapper.toMessage('P0011: invalid transition'),
          contains('estado actual'));
    });

    test('maps held balance mismatch', () {
      expect(AppErrorMapper.toMessage('P0012: mismatch'),
          contains('inconsistencia'));
    });

    test('maps expired window', () {
      expect(AppErrorMapper.toMessage('P0013: report window expired'),
          contains('ya expiro'));
    });

    test('maps driver banned', () {
      expect(AppErrorMapper.toMessage('P0015: driver banned'),
          contains('suspendido'));
    });

    test('maps overlapping booking', () {
      expect(AppErrorMapper.toMessage('P0016: overlapping'),
          contains('Ya tienes un viaje'));
    });

    test('maps auto expired', () {
      expect(AppErrorMapper.toMessage('P0017: auto expired'),
          contains('expiro'));
    });

    test('maps cancellation cooldown', () {
      expect(AppErrorMapper.toMessage('P0018: cooldown'),
          contains('Espera 15 minutos'));
    });

    test('maps user blocked', () {
      expect(AppErrorMapper.toMessage('P0019: user blocked'),
          contains('bloqueado'));
    });

    test('maps terms not accepted', () {
      expect(AppErrorMapper.toMessage('terms_not_accepted'),
          contains('Debes aceptar'));
    });

    test('maps driver license required', () {
      expect(AppErrorMapper.toMessage('driver_license_required'),
          contains('licencia vigente'));
    });

    test('maps vehicle required', () {
      expect(
          AppErrorMapper.toMessage(
              'users_profile_driver_vehicle_required_ck'),
          contains('conductor'));
    });

    test('maps cannot book own ride', () {
      expect(AppErrorMapper.toMessage('cannot_book_own_ride'),
          contains('publicaste'));
    });

    test('maps review errors', () {
      expect(AppErrorMapper.toMessage('P0014: review already submitted'),
          contains('resena'));
    });

    test('maps favorite self forbidden', () {
      final msg = AppErrorMapper.toMessage('favorite_self_forbidden');
      expect(msg, anyOf(contains('favoritos'), contains('permisos')));
    });

    test('maps payment provider disabled', () {
      expect(AppErrorMapper.toMessage('payment_provider_disabled'),
          contains('deshabilitadas'));
    });

    test('maps Fintoc not configured', () {
      expect(AppErrorMapper.toMessage('fintoc_secret_key_missing'),
          contains('Fintoc'));
    });

    test('maps supabase not configured', () {
      expect(AppErrorMapper.toMessage('supabase_not_configured'),
          contains('SUPABASE_URL'));
    });
  });
}
