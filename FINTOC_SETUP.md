# Fintoc — Setup Sandbox (Modo Test)

Guía para dejar operativa la pasarela de pago **Fintoc en modo sandbox**
(keys de test). Estado: **✅ CONFIGURADO Y VERIFICADO end-to-end** (2026-08-25).

---

## 1. Keys

| # | Key | Estado |
|---|-----|--------|
| 1 | **Secret Key de TEST** (`sk_test_...`) | ✅ Configurada como secret `FINTOC_SECRET_KEY` |
| 2 | **Webhook Secret** (`whsec_test_...`) | ✅ Configurada como secret `FINTOC_WEBHOOK_SECRET` |
| 3 | Public Key (`pk_test_...`) | ⚠️ No necesaria para Checkout Sessions |

El secret key valida contra la API de Fintoc (sesiones de test creadas OK).
El webhook secret coincide con el endpoint registrado en Fintoc Dashboard.

## 2. Estado de Supabase

- ✅ Migración 33 aplicada (`supabase db push`)
- ✅ `create-topup-intent` desplegada (v13, `--no-verify-jwt`)
- ✅ `fintoc-webhook` desplegada (`--no-verify-jwt`)
- ✅ Secrets: `FINTOC_SECRET_KEY`, `FINTOC_WEBHOOK_SECRET`, `PAYMENT_PROVIDER=fintoc`
- ⚠️ `APP_BASE_URL` no está seteada → usa default `https://turnoapp.cl`
  (setearla cuando el dominio esté publicado)

## 3. Webhook en Fintoc Dashboard

✅ **Ya registrado** (endpoint `we_7yG91kqCXXx3an4Y`):
- URL: `https://zawaevytpkvejhekyokw.supabase.co/functions/v1/fintoc-webhook`
- Eventos: `checkout_session.finished`, `checkout_session.expired`,
  `payment_intent.succeeded`, `payment_intent.failed`, `payment_intent.rejected`,
  `payment_intent.pending`, `payment_intent.expired`

## 4. Pruebas realizadas (2026-08-25)

| Prueba | Resultado |
|--------|-----------|
| Crear sesión con `sk_test_` directo a Fintoc API | ✅ |
| `create-topup-intent` vía edge function (JWT usuario) | ✅ `redirect_url` + fila `pending` en `fintoc_payments` |
| Webhook `checkout_session.finished` + `pi.succeeded` (firma HMAC válida) | ✅ `credit_wallet_topup` → wallet +2000, status `approved` |
| Webhook duplicado (idempotencia) | ✅ no duplica saldo |
| Firma inválida | ✅ 401 |
| Webhook `payment_intent.succeeded` | ✅ acredita vía `payment_intent_id` |
| Webhook `checkout_session.finished` + `pi.failed` | ✅ marca `failed`, NO acredita |
| Usuario de test | `fintoc-test@turno.app` / `Sandbox123!` (wallet con 2000 CLP de prueba) |

## 5. Prueba manual end-to-end (opcional, con navegador)

1. App iOS → Wallet → Recargar → monto → abre `pay.fintoc.com/...` en Safari
2. En el checkout de test: banco de test → usuario `41614850-3` / `jonsnow`
   (o `user_good` / `pass_good` en flujos antiguos)
3. Autorizar transferencia (MFA simulado según últimos dígitos del monto:
   `01`→`0000`, `04`→`000000`, `05`→`['00','00','00']`)
4. Fintoc envía `checkout_session.finished` + `payment_intent.succeeded` →
   webhook acredita la billetera
5. Redirección final a `https://turnoapp.cl/wallet?topup=success` — cuando
   el dominio esté publicado con universal links, reabre la app; mientras
   tanto la billetera se actualiza igual vía realtime + lifecycle resume

### Simular escenarios

| Escenario | Cómo |
|-----------|------|
| Pago exitoso | Credenciales de test normales (`41614850-3` / `jonsnow`) |
| MFA security device | Monto terminado en `01` → código `0000` |
| MFA SMS | Monto terminado en `04` → código `000000` |
| Pago fallido | Credencial/código MFA incorrecto |
| Pending → Success | Cuenta origen `512347890123` |

## 6. Pasar a producción (después del sandbox)

- Reemplazar `FINTOC_SECRET_KEY` por la **live** (`sk_live_...`)
- Crear/registrar el webhook en modo **live** (la secret de live es distinta
  a la de test) → actualizar `FINTOC_WEBHOOK_SECRET`
- Setear `APP_BASE_URL` al dominio publicado y verificar universal links
  (AASA + associated domains en la app)
- Probar con un monto real pequeño antes de habilitar para todos
