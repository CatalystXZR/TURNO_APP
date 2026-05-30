class AppErrorMapper {
  AppErrorMapper._();

  static String toMessage(
    Object error, {
    String fallback = 'No pudimos completar la operacion. Intenta nuevamente.',
  }) {
    final raw = error.toString();
    final text = raw.toLowerCase();

    if (text.contains('unauthorized') ||
        text.contains('p0001') ||
        text.contains('jwt') ||
        text.contains('token') ||
        text.contains('session')) {
      return 'Sesion expirada. Cierra sesion y vuelve a iniciar.';
    }

    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection closed') ||
        text.contains('timed out')) {
      return 'No hay conexion a internet. Revisa tu red e intentalo otra vez.';
    }

    if (text.contains('invalid login credentials') ||
        text.contains('invalid_credentials')) {
      return 'Correo o contrasena incorrectos.';
    }

    if (text.contains('user already registered') ||
        text.contains('already registered')) {
      return 'Este correo ya tiene una cuenta. Inicia sesion.';
    }

    if (text.contains('email not confirmed')) {
      return 'Debes confirmar tu correo antes de ingresar.';
    }

    if (text.contains('supabase_not_configured') ||
        text.contains('your_project.supabase.co') ||
        text.contains('your_anon_key')) {
      return 'Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY en la app.';
    }

    if (text.contains('signup is disabled')) {
      return 'El registro esta deshabilitado en Supabase. Activalo en Auth > Providers > Email.';
    }

    if (text.contains('database error saving new user')) {
      return 'No se pudo crear el usuario por una configuracion de base de datos (trigger/policies).';
    }

    if (text.contains('permission denied') ||
        text.contains('row-level security')) {
      return 'Tu proyecto de Supabase no permite leer referencias publicas (universidades/campus). Ejecuta migraciones 06 y 07.';
    }

    if (text.contains('user not allowed')) {
      return 'No tienes permitido registrarte con este correo.';
    }

    if (text.contains('p0001') || text.contains('unauthorized')) {
      return 'Tu sesion expiro. Vuelve a iniciar sesion.';
    }

    if (text.contains('p0002') || text.contains('ride unavailable')) {
      return 'Este turno ya no esta disponible.';
    }

    if (text.contains('p0003') || text.contains('already booked')) {
      return 'Ya tienes una reserva en este turno.';
    }

    if (text.contains('p0004') || text.contains('insufficient balance')) {
      return 'Saldo insuficiente. Recarga tu billetera para continuar.';
    }

    if (text.contains('p0005') || text.contains('already processed')) {
      return 'La reserva ya fue procesada.';
    }

    if (text.contains('p0006') || text.contains('forbidden')) {
      return 'No tienes permisos para realizar esta accion.';
    }

    if (text.contains('p0008') || text.contains('wait_time_not_elapsed')) {
      return 'Aun no pasan los 10 minutos de espera. Intenta reportar mas tarde.';
    }

    if (text.contains('p0010') || text.contains('ride_departed')) {
      return 'Este viaje ya inicio.';
    }

    if (text.contains('p0011') ||
        text.contains('invalid_dispatch_transition') ||
        text.contains('booking_not_active') ||
        text.contains('cannot_cancel_started_trip') ||
        text.contains('passenger_not_boarded')) {
      return 'No puedes ejecutar esa accion en el estado actual del viaje.';
    }

    if (text.contains('p0012') || text.contains('held_balance_mismatch')) {
      return 'Detectamos una inconsistencia de saldo retenido. Intenta actualizar.';
    }

    if (text.contains('p0013') ||
        text.contains('report_window_expired') ||
        text.contains('cancel_window_expired')) {
      return 'La ventana para esta accion ya expiro.';
    }

    if (text.contains('p0015') ||
        text.contains('driver_banned_now') ||
        text.contains('is_driver_banned_now') ||
        text.contains('vehicle_suspended')) {
      return 'Tu cuenta o vehiculo esta suspendido temporalmente por strikes.';
    }

    if (text.contains('p0014') ||
        text.contains('review_only_completed_trip') ||
        text.contains('review_already_submitted') ||
        text.contains('review_window_expired') ||
        text.contains('invalid_review_stars')) {
      return 'No fue posible guardar la resena con esos datos o en este estado.';
    }

    if (text.contains('favorite_self_forbidden') ||
        text.contains('invalid_favorite_target') ||
        text.contains('favorite_target_not_found')) {
      return 'No fue posible actualizar favoritos para ese usuario.';
    }

    if (text.contains('cannot_book_own_ride')) {
      return 'No puedes reservar un turno que publicaste tu mismo.';
    }

    if (text.contains('terms_not_accepted')) {
      return 'Debes aceptar terminos y condiciones para continuar.';
    }

    if (text.contains('driver_license_required')) {
      return 'Debes declarar licencia vigente para activar acciones de conductor.';
    }

    if (text.contains('users_profile_driver_vehicle_required_ck')) {
      return 'Para ser conductor debes ingresar marca, modelo, version, puertas y patente.';
    }

    if (text.contains('minimum amount')) {
      return 'El monto minimo permitido es de \$2.000 CLP.';
    }

    if (text.contains('maximum amount')) {
      return 'El monto maximo por recarga es de \$200.000 CLP.';
    }

    if (text.contains('payment provider error') ||
        text.contains('payment_provider_error')) {
      return 'El proveedor de pagos no respondio. Intenta nuevamente.';
    }

    if (text.contains('payment_provider_disabled')) {
      return 'Las recargas estan temporalmente deshabilitadas. Vuelve a intentar mas tarde.';
    }

    if (text.contains('overlapping_booking') || text.contains('p0016')) {
      return 'Ya tienes un viaje a esta hora.';
    }

    if (text.contains('fintoc_secret_key_missing') ||
        text.contains('provider_not_connected') ||
        text.contains('not_implemented')) {
      return 'Fintoc aun no esta configurado. Revisa FINTOC_SECRET_KEY en las Edge Function Secrets.';
    }

    if (text.contains('p0017') ||
        text.contains('auto_expired') ||
        text.contains('passenger_no_board')) {
      return 'La reserva expiro porque nunca confirmaste abordaje.';
    }

    if (text.contains('p0018') || text.contains('cancellation_cooldown')) {
      return 'Cancelaste este turno recientemente. Espera 15 minutos para volver a reservarlo.';
    }

    if (text.contains('double_book_guard') ||
        text.contains('overlapping_ride')) {
      return 'Ya tienes una reserva en un horario que se cruza con este turno.';
    }

    if (text.contains('no_show_threshold') ||
        text.contains('report_too_late')) {
      return 'Ya no puedes reportar. El viaje finalizo.';
    }

    if (text.contains('p0019') || text.contains('user_blocked')) {
      return 'No puedes interactuar con este usuario porque uno de los dos ha bloqueado al otro.';
    }

    return fallback;
  }
}
