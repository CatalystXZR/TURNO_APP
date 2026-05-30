/**
 * Turno — Migration 22: Hardening close gaps (sandbox, delete account, fix complete_ride_manual)
 * Sandbox-only release. All functions idempotent with CREATE OR REPLACE.
 */

-- =============================================================
-- 1) sandbox_topup — Adds balance directly without payment provider
-- =============================================================
CREATE OR REPLACE FUNCTION public.sandbox_topup(p_amount int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sesion requerida' USING ERRCODE = 'P0001';
  END IF;

  IF p_amount <= 0 OR p_amount > 200000 THEN
    RAISE EXCEPTION 'Monto invalido' USING ERRCODE = 'P0009';
  END IF;

  UPDATE wallets
  SET balance_available = balance_available + p_amount,
      updated_at = now()
  WHERE user_id = v_user;

  IF NOT FOUND THEN
    INSERT INTO wallets (user_id, balance_available, balance_held)
    VALUES (v_user, p_amount, 0);
  END IF;

  INSERT INTO transactions (user_id, type, amount, metadata)
  VALUES (
    v_user,
    'topup',
    p_amount,
    jsonb_build_object('method', 'sandbox', 'reason', 'sandbox_topup_dev')
  );
END $$;

-- =============================================================
-- 2) sandbox_withdraw — Requests payout directly without provider
-- =============================================================
CREATE OR REPLACE FUNCTION public.sandbox_withdraw(p_amount int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_withdrawal_id uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sesion requerida' USING ERRCODE = 'P0001';
  END IF;

  IF p_amount < 20000 THEN
    RAISE EXCEPTION 'Monto minimo de retiro: $20.000 CLP' USING ERRCODE = 'P0009';
  END IF;

  UPDATE wallets
  SET balance_available = balance_available - p_amount,
      updated_at = now()
  WHERE user_id = v_user
    AND balance_available >= p_amount;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Saldo insuficiente' USING ERRCODE = 'P0004';
  END IF;

  INSERT INTO withdrawals (driver_id, amount, status)
  VALUES (v_user, p_amount, 'requested')
  RETURNING id INTO v_withdrawal_id;

  INSERT INTO transactions (user_id, type, amount, metadata)
  VALUES (
    v_user,
    'withdrawal_request',
    -p_amount,
    jsonb_build_object('withdrawal_id', v_withdrawal_id, 'method', 'sandbox')
  );
END $$;

-- =============================================================
-- 3) delete_user_account — Deletes user data (Apple compliance)
-- =============================================================
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sesion requerida' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM bookings WHERE passenger_id = v_user;
  DELETE FROM rides WHERE driver_id = v_user;
  DELETE FROM transactions WHERE user_id = v_user;
  DELETE FROM withdrawals WHERE driver_id = v_user;
  DELETE FROM mp_payments WHERE user_id = v_user;
  DELETE FROM strikes WHERE driver_id = v_user;
  DELETE FROM wallets WHERE user_id = v_user;
  DELETE FROM users_profile WHERE id = v_user;
  DELETE FROM auth.users WHERE id = v_user;
END $$;

-- =============================================================
-- 4) Fix complete_ride_manual — Same accounting as driver_complete_trip
--    No rides.completed_at (column doesn't exist), no ride_complete type.
-- =============================================================
CREATE OR REPLACE FUNCTION public.complete_ride_manual(p_ride_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride record;
  v_booking record;
  v_passenger uuid;
  v_amount int;
  v_fee int;
  v_driver_net int;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sesion requerida' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id AND driver_id = v_user;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ride no encontrado o no eres el conductor' USING ERRCODE = 'P0002';
  END IF;

  IF v_ride.status <> 'active' THEN
    RAISE EXCEPTION 'El ride no esta activo' USING ERRCODE = 'P0005';
  END IF;

  FOR v_booking IN
    SELECT b.id, b.passenger_id, b.amount_total, b.dispatch_status,
           greatest(coalesce(v_ride.driver_net_amount, b.amount_total), 0) AS driver_net,
           greatest(b.amount_total - greatest(coalesce(v_ride.driver_net_amount, b.amount_total), 0), 0) AS fee
    FROM bookings b
    WHERE b.ride_id = p_ride_id
      AND b.status = 'reserved'
    FOR UPDATE OF b
  LOOP
    v_passenger := v_booking.passenger_id;
    v_amount := v_booking.amount_total;
    v_driver_net := v_booking.driver_net;
    v_fee := v_booking.fee;

    UPDATE wallets
    SET balance_held = balance_held - v_amount,
        updated_at = now()
    WHERE user_id = v_passenger
      AND balance_held >= v_amount;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'held_balance_mismatch' USING ERRCODE = 'P0012';
    END IF;

    UPDATE wallets
    SET balance_available = balance_available + v_driver_net,
        updated_at = now()
    WHERE user_id = v_user;

    UPDATE bookings
    SET status = 'completed',
        dispatch_status = 'completed',
        confirmed_at = coalesce(confirmed_at, now()),
        trip_started_at = coalesce(trip_started_at, now()),
        trip_completed_at = now()
    WHERE id = v_booking.id;

    INSERT INTO transactions (user_id, booking_id, type, amount, metadata)
    VALUES (
      v_passenger,
      v_booking.id,
      'release_to_driver',
      0,
      jsonb_build_object(
        'driver_id', v_user,
        'platform_fee', v_fee,
        'driver_net_amount', v_driver_net,
        'settled_at', now()
      )
    );

    INSERT INTO transactions (user_id, booking_id, type, amount, metadata)
    VALUES (
      v_user,
      v_booking.id,
      'release_to_driver',
      v_driver_net,
      jsonb_build_object(
        'passenger_id', v_passenger,
        'platform_fee', v_fee,
        'gross_amount', v_amount
      )
    );

    PERFORM public.log_booking_event(
      v_booking.id,
      p_ride_id,
      v_user,
      'driver',
      v_booking.dispatch_status,
      'completed'::booking_dispatch_status,
      'driver_completed_ride_manual',
      jsonb_build_object(
        'gross_amount', v_amount,
        'driver_net_amount', v_driver_net,
        'platform_fee', v_fee
      )
    );
  END LOOP;

  PERFORM public.set_ride_completed_if_no_open_bookings(p_ride_id);
END $$;

-- =============================================================
-- 5) Grants for authenticated role
-- =============================================================
GRANT EXECUTE ON FUNCTION public.sandbox_topup(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sandbox_withdraw(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_ride_manual(uuid) TO authenticated;
