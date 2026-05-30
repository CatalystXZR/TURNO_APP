# PLAN MAESTRO — UniRide (Turno) v2

> **Objetivo:** Migrar de Mercado Pago a Fintoc, completar Supabase Realtime, pasar de Vercel (PWA) a iOS nativo con Codemagic, y limpiar documentación.
> **Fecha:** Mayo 2026
> **Stack final:** Flutter iOS nativo + Supabase + Fintoc + Codemagic

---

## RESUMEN DE DECISIONES

| Decisión | Elección | Razón |
|----------|----------|-------|
| Pasarela de pago | **Fintoc** (Checkout Sessions) | Reemplaza Mercado Pago. API más simple. |
| Precios | **$2.500 PUC/UCH, $2.000 resto** + fee fijo $190 | Como está en migración 13 |
| Build iOS | **Codemagic** | Capa gratuita, especializado en Flutter, code signing automático |
| Web PWA | **Conservar por ahora** | Fallback mientras se aprueba en App Store |
| Tabla de pagos | **Nueva `fintoc_payments`** | Limpia, sin legacy de MP |
| Documentación | **Un solo README.md** | Basado en DOSSIER_TECNICO.md. Los otros 18 .md se eliminan |

---

## FASES DE EJECUCIÓN

### FASE 1: Limpieza de documentación
- [ ] Consolidar todo en `README.md` (basado en `DOSSIER_TECNICO.md`)
- [ ] Eliminar 18 .md sobrantes (raíz + docs/ + turno/ios/...)
- [ ] Actualizar `.env.example` con variables Fintoc

### FASE 2: Mercado Pago → Fintoc
- [ ] Migración SQL 27: tabla `fintoc_payments`, update RPCs, drop `mp_payments`
- [ ] Edge Functions: eliminar MP/Stripe, reescribir `create-topup-intent`, crear `fintoc-webhook`
- [ ] Flutter: actualizar `wallet_service.dart`, limpiar `error_mapper.dart`

### FASE 3: Supabase Realtime
- [ ] Canal realtime en `wallet_provider` (tabla `wallets`)
- [ ] Canal realtime en `home_provider` (perfil + wallet)
- [ ] Optimizar callbacks: patch local en vez de re-fetch completo

### FASE 4: iOS Nativo + Codemagic
- [ ] Eliminar archivos Vercel
- [ ] Verificar/actualizar `ios/Info.plist`
- [ ] Configurar `codemagic.yaml`
- [ ] Documentar flujo de build y TestFlight en README

---

## FINTOC — Flujo de Integración

```
Usuario (app) → Edge Function create-topup-intent
  → POST /v2/checkout_sessions (Fintoc API)
  → Retorna redirect_url
  → Usuario paga en página Fintoc
  → Webhook fintoc-webhook recibe checkout_session.finished
  → RPC credit_wallet_topup() acredita billetera
  → Tabla fintoc_payments registra idempotencia
```

### Variables de entorno requeridas
```
FINTOC_SECRET_KEY=sk_test_xxx    # o sk_live_xxx en prod
FINTOC_WEBHOOK_SECRET=xxx        # Para validar firma de webhooks
FINTOC_PUBLIC_KEY=pk_test_xxx    # Solo si se usa SDK frontend
PAYMENT_PROVIDER=fintoc
APP_BASE_URL=https://turnoapp.cl
```

---

## REALTIME — Canales a implementar

| Canal | Tabla | Filtro | Provider |
|-------|-------|--------|----------|
| `rides-driver-$uid` | rides | driver_id | driver_rides_provider ✅ Ya existe |
| `bookings-driver-$uid` | bookings | driver_id | driver_rides_provider ✅ Ya existe |
| `bookings-passenger-$uid` | bookings | passenger_id | my_rides_provider ✅ Ya existe |
| `wallet-$uid` | wallets | user_id | wallet_provider ❌ **NUEVO** |
| `profile-$uid` | users_profile | id | home_provider ❌ **NUEVO** |

---

## ESTRUCTURA FINAL DEL REPOSITORIO

```
uniride/
├── README.md                          # Documento único
├── PLAN_MAESTRO.md                    # Este archivo (para otros chats)
├── .env.example                       # Variables Fintoc + Supabase
├── .gitignore
├── .github/
│   └── workflows/
│       └── ios-build.yml              # CI/CD iOS (si se usa GitHub Actions)
├── codemagic.yaml                     # CI/CD Codemagic
├── turno/                          # Flutter app
│   ├── pubspec.yaml
│   ├── lib/                           # Código Dart
│   │   ├── main.dart
│   │   ├── app/                       # router, theme, app
│   │   ├── core/                      # constants, supabase_client, error_mapper
│   │   ├── models/                    # 9 modelos
│   │   ├── services/                  # 13 servicios
│   │   ├── providers/                 # 8 providers (2 nuevos realtime)
│   │   ├── features/                  # 12 módulos de pantallas
│   │   └── shared/widgets/           # 7 widgets reutilizables
│   ├── ios/                           # Proyecto Xcode + Fastlane
│   ├── web/                           # PWA (conservado como fallback)
│   └── test/
└── supabase/                          # Backend
    ├── config.toml
    ├── migrations/                    # 27 migraciones
    └── functions/                     # 4 edge functions
        ├── create-topup-intent/       # Fintoc Checkout Session
        ├── fintoc-webhook/            # Webhook Fintoc
        ├── send-push-notification/    # APNs push
        └── delete-account/            # Eliminación de cuenta
```

---

## NOTAS PARA COLABORADORES / IAs

1. **Todo el contexto está en `README.md`**. Es el único doc a leer.
2. **Este `PLAN_MAESTRO.md`** es para seguir la migración paso a paso.
3. **No tocar la carpeta `web/`** — se conserva como fallback mientras se aprueba en App Store.
4. **Precios:** `enforce_ride_pricing()` trigger tiene la lógica correcta ($2.500 PUC/UCH, $2.000 resto).
5. **Variables de entorno** se pasan via `--dart-define` para Flutter y via Supabase Dashboard → Edge Function Secrets para las edge functions.
