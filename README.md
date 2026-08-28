# **README COMPLETO - TURNO**

> **Plataforma de carpooling universitario en Chile**
> iOS nativo + Supabase + Fintoc

---

### Cuentas demo

| Tipo | Email | Password |
|------|-------|----------|
| Pasajero | `pasajero@demo.com` | `demo1234` |
| Conductor | `conductor@demo.com` | `demo1234` |

Ambas cuentas tienen $50.000 CLP de saldo. El conductor tiene vehículo registrado (Toyota Yaris, patente ABC123).

Para crearlas en Supabase, ejecutar en SQL Editor:

```sql
insert into auth.users (email, encrypted_password, email_confirmed_at, raw_user_meta_data)
values
('pasajero@demo.com', crypt('demo1234', gen_salt('bf')), now(), '{"full_name":"Demo Pasajero","accepted_terms":true,"role_mode":"passenger"}'),
('conductor@demo.com', crypt('demo1234', gen_salt('bf')), now(), '{"full_name":"Demo Conductor","accepted_terms":true,"role_mode":"driver","has_valid_license":true,"vehicle_brand":"Toyota","vehicle_model":"Yaris","vehicle_plate":"ABC123"}')
on conflict (email) do nothing;

select public.credit_wallet_topup(
  (select id from auth.users where email='pasajero@demo.com'), 50000, 'demo-topup-pasajero', 50000, 0, 'demo');
select public.credit_wallet_topup(
  (select id from auth.users where email='conductor@demo.com'), 50000, 'demo-topup-conductor', 50000, 0, 'demo');
```

### Precios

| Universidad | Precio asiento | Fee plataforma | Total pasajero | Recibe conductor |
|-------------|---------------|----------------|----------------|------------------|
| PUC, UCH | $2.500 | $190 | $2.690 | $2.500 |
| Otras | $2.000 | $190 | $2.190 | $2.000 |


### Fintoc — Flujo de recarga (sandbox)

```
Usuario → Edge Function create-topup-intent
  → POST /v2/checkout_sessions (Fintoc API, modo test)
  → fintoc_payments INSERT pending
  → Retorna redirect_url
  → Usuario paga en página Fintoc (credenciales de test)
  → Webhook fintoc-webhook → RPC credit_wallet_topup() acredita billetera
```

> Keys y pasos de configuración: [`FINTOC_SETUP.md`](FINTOC_SETUP.md).

---

# DOSSIER TÉCNICO - TURNO

> **Plataforma de carpooling universitario en Chile**
> Dueños del proyecto: Agustín Puelma, Cristóbal Córdova, Carlos Ibarra
> Arquitectura y código: Matías Toledo (@catalystxzr)
> Año: 2026

---

## TABLA DE CONTENIDOS

1. [Visión General del Proyecto](#1-visión-general-del-proyecto)
2. [Arquitectura del Sistema](#2-arquitectura-del-sistema)
3. [Estructura del Repositorio](#3-estructura-del-repositorio)
4. [Stack Tecnológico y Lenguajes](#4-stack-tecnológico-y-lenguajes)
5. [Frontend — Flutter (Dart)](#5-frontend--flutter-dart)
   - 5.1. Punto de entrada (`main.dart`)
   - 5.2. Capa de aplicación (`app/`)
   - 5.3. Capa core (`core/`)
   - 5.4. Modelos de datos (`models/`)
   - 5.5. Servicios (`services/`)
   - 5.6. Providers de estado (Riverpod) (`providers/`)
   - 5.7. Features / Pantallas (`features/`)
   - 5.8. Widgets compartidos (`shared/widgets/`)
6. [Backend — Supabase](#6-backend--supabase)
   - 6.1. PostgreSQL — Esquema completo
   - 6.2. Row Level Security (RLS)
   - 6.3. Funciones RPC
   - 6.4. Triggers
   - 6.5. Índices
   - 6.6. Reglas de inmutabilidad (Ledger)
   - 6.7. Vistas operativas
   - 6.8. Evolución del esquema (33 migraciones)
7. [Edge Functions (Deno + TypeScript)](#7-edge-functions-deno--typescript)
8. [Realtime — Canales Supabase](#8-realtime--canales-supabase)
9. [Storage — Fotos de perfil](#9-storage--fotos-de-perfil)
10. [Sistema de Pagos — Fintoc](#10-sistema-de-pagos)
11. [Motor de Negocio y Reglas](#11-motor-de-negocio-y-reglas)
12. [Sistema de Despacho — Máquina de estados](#12-sistema-de-despacho--máquina-de-estados)
13. [Sistema de Strikes y Suspensiones](#13-sistema-de-strikes-y-suspensiones)
14. [Sistema de Reseñas y Favoritos](#14-sistema-de-reseñas-y-favoritos)
15. [Sistema de Notificaciones](#15-sistema-de-notificaciones)
16. [Enrutamiento y Protección de rutas](#16-enrutamiento-y-protección-de-rutas)
17. [Manejo de Errores](#17-manejo-de-errores)
18. [Despliegue y CI/CD](#18-despliegue-y-cicd)
19. [Variables de Entorno](#19-variables-de-entorno)
20. [Flujos End-to-End](#20-flujos-end-to-end)
21. [Estado actual, Pendientes y Riesgos](#21-estado-actual-pendientes-y-riesgos)
22. [Guía para colaborar en el proyecto](#22-guía-para-colaborar-en-el-proyecto)
23. [Glosario](#23-glosario)

---

## 1. VISIÓN GENERAL DEL PROYECTO

### Qué es Turno

Turno es una **app iOS nativa** de carpooling universitario en Chile. Conecta estudiantes conductores con estudiantes pasajeros que comparten trayectos entre sus comunas de origen y sus campus universitarios.

### Problema que resuelve

- Traslados universitarios caros e ineficientes
- Falta de coordinación segura entre estudiantes
- Pagos informales sin trazabilidad ni protección

### Solución

Un flujo digital claro y seguro:

```
Publicar turno → Reservar → Retener pago → Confirmar abordaje → Liberar pago
```

Con reglas de seguridad operativa: términos aceptados, licencia declarada, sistema de no-show, strikes, suspensiones y un ledger financiero auditable.

### Modelo de negocio

- **Precio por asiento:** $2.500 CLP (PUC, UCH) / $2.000 CLP (otras universidades)
- **Comisión de plataforma:** $190 CLP fijos por asiento (cobrado al pasajero)
- **El pasajero paga:** $2.690 CLP (PUC/UCH) / $2.190 CLP (otras)
- **El conductor recibe:** $2.500 CLP (PUC/UCH) / $2.000 CLP (otras)
- **La plataforma gana:** $190 CLP por asiento vendido
- **Recargo por recarga:** 1% del monto recargado (cubre costos de procesamiento)
- **Retiro mínimo:** $20.000 CLP (procesado manualmente, quincenal)

### Público objetivo

- **Universidades:** UDD, UANDES, PUC, UCH, UAI, UNAB
- **Comunas de origen:** Chicoreo, Lo Barnechea, Providencia, Vitacura, La Reina, Buin
- **Modalidad:** iOS nativo (iPhone) + fallback PWA web

---

## 2. ARQUITECTURA DEL SISTEMA

La app sigue una arquitectura **cliente liviano + backend fuerte**, donde toda la lógica crítica y financiera reside en la base de datos.

```
┌──────────────────────────────────────────────────────────┐
│                  CLIENTE (Flutter iOS)                    │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │  UI     │  │  Router  │  │ Riverpod │  │ Servicios │  │
│  │ Widgets │  │ go_router│  │  State   │  │  (Dart)   │  │
│  └────┬────┘  └──────────┘  └────┬─────┘  └─────┬─────┘  │
│       │                          │               │        │
└───────┼──────────────────────────┼───────────────┼────────┘
        │                          │               │
        ▼                          ▼               ▼
┌───────────────────────────────────────────────────────────┐
│                     SUPABASE CLOUD                        │
│  ┌────────────┐  ┌─────────────┐  ┌──────────────────┐    │
│  │  Auth      │  │ PostgREST   │  │  PostgreSQL 17   │    │
│  │  (JWT)     │  │  (REST API) │  │  + RLS + RPC     │    │
│  └─────┬──────┘  └──────┬──────┘  └────────┬─────────┘    │
│        │                │                   │              │
│  ┌─────┴────────────────┴───────────────────┴──────────┐  │
│  │         Edge Functions (Deno/TS) — 4 funciones      │  │
│  │  ┌────────────────────┐  ┌──────────────────────┐   │  │
│  │  │ create-topup-intent│  │    fintoc-webhook    │   │  │
│  │  └────────────────────┘  └──────────────────────┘   │  │
│  │  ┌────────────────────┐  ┌──────────────────────┐   │  │
│  │  │  send-push-notif   │  │   delete-account     │   │  │
│  │  └────────────────────┘  └──────────────────────┘   │  │
│  └─────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐ │
│  │        Realtime Channels (5 canales activos)         │ │
│  │  rides-driver | bookings-driver | bookings-passenger │ │
│  │        wallet | profile (home)                       │ │
│  └──────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  Supabase Storage (profile-photos bucket)            │ │
│  └──────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────┐
│    FINTOC API     │
│ (Checkout Sessions)│
└───────────────────┘
```

### Nodos del sistema

| Nodo | Tecnología | Responsabilidad |
|------|-----------|-----------------|
| **A — Cliente** | Flutter iOS (Dart) | UI, captura de intención, validación visual, navegación |
| **B — Auth** | Supabase Auth | Identidad, sesiones JWT, trigger de bootstrap de perfil |
| **C — API REST** | PostgREST | CRUD expuesto, RLS filtra acceso por usuario/rol |
| **D — Base de datos** | PostgreSQL 17 | Fuente única de verdad: constraints, triggers, RPCs, ledger |
| **E — Edge Functions** | Deno + TypeScript | Integraciones externas seguras (pagos Fintoc, push, delete account) |
| **F — Pagos** | Fintoc | Checkout Sessions, webhook de confirmación |
| **G — Realtime** | Supabase Realtime | 5 canales PostgreSQL (rides, bookings, wallet, profile) |
| **H — Push** | APNs (Apple) | Notificaciones push nativas en iOS |

### Patrón de seguridad

- **Security by default:** Row Level Security (RLS) en todas las tablas sensibles
- **Operaciones financieras:** Solo a través de funciones RPC `SECURITY DEFINER` (ejecutan con privilegios elevados, ignorando RLS)
- **Ledger inmutable:** Las transacciones no se pueden actualizar ni borrar (PostgreSQL rules)
- **Webhooks:** Verificación HMAC (producción) + idempotencia por `external_payment_id`

---

## 3. ESTRUCTURA DEL REPOSITORIO

```
uniride/                                    # Raíz del monorepo
├── README.md                               # Documentación completa del proyecto
├── PLAN_MAESTRO.md                         # Guía de migración para otros chats
├── codemagic.yaml                          # CI/CD automático iOS → TestFlight
├── .env.example                            # Template de variables de entorno
├── .gitignore
│
├── .github/
│   └── workflows/                          # CI/CD (vacío, listo para iOS via GitHub Actions)
│
├── turno/                               # ═══ FRONTEND: App Flutter ═══
│   ├── pubspec.yaml                        # Dependencias Flutter (SDK 3.0+, Riverpod, go_router, etc.)
│   ├── analysis_options.yaml               # Reglas de lint de Dart
│   ├── codemagic.yaml                      # (raíz) CI/CD Codemagic
│   ├── ios/                                # Proyecto Xcode nativo
│   ├── web/                                # PWA conservada como fallback
│   ├── test/                               # Tests unitarios y de widgets
│   └── lib/                                # ═══ CÓDIGO FUENTE PRINCIPAL ═══
│       ├── main.dart                       # Punto de entrada de la app
│       ├── app/                            # Configuración (app.dart, router.dart, theme.dart)
│       ├── core/                           # Infraestructura (supabase_client, constants, error_mapper)
│       ├── models/                         # 9 modelos de datos (DTOs inmutables)
│       ├── services/                       # 13 servicios de comunicación con backend
│       ├── providers/                      # 8 providers Riverpod (StateNotifier + canales realtime)
│       ├── features/                       # 12 módulos de pantallas
│       └── shared/widgets/                 # 7 widgets reutilizables
│
├── supabase/                               # ═══ BACKEND: Supabase ═══
│   ├── config.toml                         # Config del CLI de Supabase
│   ├── migrations/                         # 33 migraciones SQL versionadas (00-33)
│   └── functions/                          # 4 Edge Functions (Deno + TypeScript)
│       ├── create-topup-intent/            # Crea sesión de pago Fintoc
│       ├── fintoc-webhook/                 # Recibe webhooks de Fintoc
│       ├── send-push-notification/         # Envía push APNs
│       └── delete-account/                 # Elimina cuenta (compliance Apple)
```
│       │   ├── profile/                    # Perfil
│       │   │   └── edit_profile_screen.dart# Editar perfil, foto, vehículo, eliminar cuenta
│       │   └── legal/                      # Legal
│       │       ├── terms_screen.dart       # Términos y condiciones
│       │       ├── privacy_policy_screen.dart # Política de privacidad
│       │       └── support_screen.dart     # Soporte + botón de pánico
│       └── shared/widgets/                 # Widgets reutilizables
│           ├── app_snackbar.dart           # SnackBar estilizado para feedback
│           ├── decorative_background.dart  # Fondo decorativo con gradientes y blobs
│           ├── loading_overlay.dart        # Overlay de carga con spinner
│           ├── turno_card.dart             # Card de turno para listados
│           ├── booking_flow_buttons.dart   # Botones contextuales del flujo de despacho
│           ├── review_dialog.dart          # Diálogo para dejar reseña (estrellas + comentario)
│           └── ride_time_status.dart       # Badge de tiempo relativo del turno
│
├── supabase/                               # ═══ BACKEND: Supabase ═══
│   ├── config.toml                         # Config del CLI de Supabase (local dev)
│   ├── migrations/                         # 33 migraciones SQL versionadas (00-33)

---

## 4. STACK TECNOLÓGICO Y LENGUAJES

| Capa | Tecnología | Versión | Por qué |
|------|-----------|---------|---------|
| **Frontend** | Flutter | 3.29+ | UI unificada, iOS nativo + fallback web |
| **Lenguaje frontend** | Dart | >=3.0.0 | Tipado fuerte, async nativo, compilación nativa a ARM64 |
| **Navegación** | go_router | 13.x | Enrutamiento declarativo con guards de autenticación |
| **Estado** | flutter_riverpod | 2.5+ | Estado escalable y testeable, 8 providers con canales realtime |
| **Backend** | Supabase Cloud | — | Stack administrado: Postgres + Auth + Realtime + Storage + Edge Functions |
| **Base de datos** | PostgreSQL | 17 | Robustez, ACID, triggers, RPCs, RLS nativo |
| **Edge Functions** | Deno + TypeScript | std@0.177.0 | Integraciones externas seguras (pagos Fintoc, push APNs) |
| **Pagos** | Fintoc | Checkout Sessions | Proveedor chileno, webhook oficial + metadata custom |
| **Realtime** | Supabase Realtime | — | 5 canales PostgreSQL (rides, bookings, wallet, profile) |
| **Push** | APNs (Apple) | HTTP/2 + ES256 | Notificaciones nativas iOS |
| **Deploy iOS** | Codemagic | — | CI/CD automático, code signing, TestFlight |
| **Tipografía** | Google Fonts (Plus Jakarta Sans) | — | Tipografía moderna y legible |

---

## 5. FRONTEND — FLUTTER (DART)

### Estructura de capas

```
lib/
├── main.dart                    # Bootstrap: inicializa Supabase, Riverpod, locale
├── app/                         # Capa de aplicación (config global)
├── core/                        # Capa de infraestructura (config, constantes, errores)
├── models/                      # Capa de datos (clases inmutables)
├── services/                    # Capa de servicios (comunicación con backend)
├── providers/                   # Capa de estado (Riverpod StateNotifier)
├── features/                    # Capa de presentación (pantallas por módulo)
└── shared/widgets/              # Widgets reutilizables transversales
```

### 5.1. Punto de entrada — `main.dart`

**Archivo:** `turno/lib/main.dart`

**Responsabilidad:** Bootstrap de la aplicación.

**Flujo de inicio:**
1. `WidgetsFlutterBinding.ensureInitialized()` — prepara el binding de Flutter
2. `initializeDateFormatting('es', null)` — inicializa formato de fechas en español (para `intl`)
3. `SupabaseConfig.ensureConfigured()` — valida que SUPABASE_URL y SUPABASE_ANON_KEY estén definidos
4. `SupabaseConfig.initialize()` — inicializa el cliente de Supabase
5. `NotificationService.instance.initialize()` — inicializa notificaciones locales (solo iOS)
6. `PushNotificationService.instance.initialize()` — inicializa push notifications (solo iOS)
7. `runApp(const ProviderScope(child: Turno()))` — monta la app con Riverpod

Si la inicialización falla, muestra `_ConfigurationErrorApp` con instrucciones para configurar las variables.

### 5.2. Capa de aplicación — `app/`

#### `app.dart` — Widget raíz

**Archivo:** `turno/lib/app/app.dart` (31 líneas)

Crea un `MaterialApp.router` con:
- `theme: AppTheme.light` — tema visual completo
- `routerConfig: appRouter` — configuración de go_router
- `debugShowCheckedModeBanner: false` — sin banner de debug

#### `router.dart` — Enrutamiento

**Archivo:** `turno/lib/app/router.dart` (120 líneas)

Configura `GoRouter` con:

**Rutas definidas:**

| Ruta | Pantalla | Acceso |
|------|----------|--------|
| `/login` | `LoginScreen` | Público |
| `/register` | `RegisterScreen` | Público |
| `/home` | `HomeScreen` | Autenticado |
| `/publish` | `PublishRideScreen` | Autenticado |
| `/search` | `SearchRidesScreen` | Autenticado |
| `/booking/:rideId` | `BookingScreen` | Autenticado |
| `/wallet` | `WalletScreen` | Autenticado |
| `/my-rides` | `MyRidesScreen` | Autenticado |
| `/arrival` | `ArrivalScreen` | Autenticado |
| `/active-trip/:bookingId` | `ActiveTripScreen` | Autenticado |
| `/driver-ride/:rideId` | `DriverActiveRideScreen` | Autenticado |
| `/driver-rides` | `DriverRidesScreen` | Autenticado |
| `/terms` | `TermsScreen` | Público |
| `/privacy` | `PrivacyPolicyScreen` | Público |
| `/support` | `SupportScreen` | Público |
| `/favorites` | `FavoritesScreen` | Autenticado |
| `/profile/edit` | `EditProfileScreen` | Autenticado |
| `/notifications` | `NotificationsScreen` | Autenticado |

**Guard de autenticación (`redirect`):**
- Si no hay sesión y la ruta no es pública → redirige a `/login`
- Si hay sesión y la ruta es de auth → redirige a `/home`
- Escucha `onAuthStateChange` de Supabase para re-evaluar automáticamente

**Clase auxiliar:** `GoRouterRefreshStream` — convierte el stream de auth de Supabase en un `ChangeNotifier` para que GoRouter reaccione a cambios de sesión.

#### `theme.dart` — Tema visual

**Archivo:** `turno/lib/app/theme.dart` (182 líneas)

Define el sistema de diseño completo:

**Paleta de colores:**

| Token | Color | Uso |
|-------|-------|-----|
| `primary` | `#1F9DFF` | Azul principal — botones, acentos |
| `primaryDark` | `#050D1B` | Azul oscuro — fondos de overlay |
| `accent` | `#6EEBFF` | Cyan claro — acentos secundarios |
| `danger` | `#BA3E5A` | Rojo — errores, acciones destructivas |
| `warning` | `#D39A2F` | Amarillo — advertencias |
| `surface` | `#F1F7FF` | Blanco azulado — fondo de scaffold |
| `onSurface` | `#0D1728` | Azul muy oscuro — texto principal |
| `subtle` | `#5C6F8B` | Gris azulado — texto secundario |
| `border` | `#CFE0F4` | Gris claro — bordes |

**Tipografía:** Google Fonts — **Plus Jakarta Sans** (no Inter como dice el README antiguo)

**Componentes estilizados:**
- Cards: borde redondeado 20px, sin elevación, borde sutil
- Inputs: borde redondeado 14px, fill suave
- Botones elevados: altura 52px, borde redondeado 14px
- Chips: borde redondeado 12px
- SnackBars: floating, fondo primaryDark
- Bottom sheets: drag handle, borde redondeado 24px arriba

### 5.3. Capa core — `core/`

#### `supabase_client.dart` — Configuración de Supabase

**Archivo:** `turno/lib/core/supabase_client.dart` (61 líneas)

Clase `SupabaseConfig` (singleton):
- Lee `SUPABASE_URL` y `SUPABASE_ANON_KEY` desde `--dart-define` (con defaults embebidos para dev)
- `ensureConfigured()` — lanza error si las credenciales no están definidas
- `initialize()` — llama `Supabase.initialize()`
- `client` — getter al `Supabase.instance.client`

> **Nota de seguridad:** Los defaults embebidos son para desarrollo local. En producción se deben usar `--dart-define`.

#### `constants.dart` — Constantes de negocio

**Archivo:** `turno/lib/core/constants.dart` (277 líneas)

Contiene **TODO** el conocimiento de negocio hardcodeado:

**Precios:**
- `seatPriceCLP = 2000` — precio base por asiento
- `platformFeeFixedCLP = 190` — comisión fija de plataforma
- `minWithdrawalCLP = 20000` — mínimo para retirar
- `minTopupCLP = 2000` / `maxTopupCLP = 200000` — límites de recarga
- `topupFeePct = 0.01` — 1% de fee por recarga

**Legal:**
- `termsVersion = 'v1.1-legal-strikes'`
- `waitTimeMinutesNoShow = 10` — minutos mínimos para reportar no-show
- `lateCancellationHours = 2` — horas para cancelación tardía (strike)
- `strikeBanMonths = 2` — meses de suspensión por 2 strikes

**Comunas permitidas:** Chicoreo, Lo Barnechea, Providencia, Vitacura, La Reina, Buin

**Universidades con IDs fijos:** 6 universidades (UDD, UANDES, PUC, UCH, UNAB, UAI) con UUIDs determinísticos

**Campus con IDs fijos:** ~23 campus asociados a las universidades, cada uno con UUID determinístico y comuna

> **Importante:** Los UUIDs fijos en las constantes coinciden con los del seed migration (`00000000000004_seed.sql`). Esto permite fallback local si la DB no responde.

#### `error_mapper.dart` — Mapeo de errores

**Archivo:** `turno/lib/core/error_mapper.dart` (195 líneas)

Traduce errores técnicos de Supabase/PostgreSQL a mensajes amigables en español:

| Patrón detectado | Mensaje al usuario |
|-----------------|-------------------|
| `unauthorized`, `jwt`, `token` | "Sesión expirada. Cierra sesión y vuelve a iniciar." |
| `socketexception`, `failed host lookup` | "No hay conexión a internet." |
| `invalid login credentials` | "Correo o contraseña incorrectos." |
| `p0004`, `insufficient balance` | "Saldo insuficiente. Recarga tu billetera." |
| `p0016`, `overlapping_booking` | "Ya tienes un viaje a esta hora." |
| `p0008`, `wait_time_not_elapsed` | "Aún no pasan los 10 minutos de espera." |
| `p0015`, `driver_banned_now` | "Tu cuenta o vehículo está suspendido por strikes." |
| `p0017`, `auto_expired` | "La reserva expiró porque nunca confirmaste abordaje." |
| `cannot_book_own_ride` | "No puedes reservar un turno que publicaste tú mismo." |
| `terms_not_accepted` | "Debes aceptar términos y condiciones." |
| `driver_license_required` | "Debes declarar licencia vigente." |
| ... y ~30 casos más | |

### 5.4. Modelos de datos — `models/`

Todas las clases son **inmutables** (solo getters, no setters) con factory `fromJson` para deserializar respuestas de la API.

#### `enums.dart` — Enumeraciones

| Enum | Valores | Uso |
|------|---------|-----|
| `RoleMode` | `passenger`, `driver` | Modo del usuario en la app |
| `BookingStatus` | `reserved`, `cancelled`, `completed`, `noShow` | Estado global de la reserva |
| `BookingDispatchStatus` | `reserved` → `accepted` → `driverArriving` → `driverArrived` → `passengerBoarded` → `inProgress` → `completed` / `cancelled` / `noShow` | Máquina de estados del despacho |
| `RideDirection` | `toCampus`, `fromCampus` | Dirección del turno |
| `TxType` | `topup`, `bookingHold`, `releaseToDriver`, `platformFee`, `refund`, `withdrawalRequest`, `withdrawalPaid`, `penalty` | Tipo de transacción en el ledger |

#### `ride.dart` — Modelo de Turno

**Archivo:** `turno/lib/models/ride.dart`

Representa un turno publicado por un conductor.

**Campos clave:**
- `id`, `driverId`, `universityId`, `campusId`, `originCommune`
- `meetingPoint` (punto de encuentro), `isRadial` (servicio puerta a puerta)
- `direction` (hacia/desde campus), `departureAt` (hora de salida)
- `seatPrice`, `platformFee`, `driverNetAmount` — desglose financiero
- `seatsTotal`, `seatsAvailable` — capacidad
- `status` — `active`, `cancelled`, `completed`
- Campos join: `driverName`, `driverRating`, `universityName`, `campusName`

**Métodos útiles:**
- `isFull` — true si `seatsAvailable == 0`
- `isActive` — true si `status == 'active'`
- `directionLabel` — "Hacia campus" o "Desde campus"

#### `booking.dart` — Modelo de Reserva

**Archivo:** `turno/lib/models/booking.dart`

Representa una reserva de un pasajero en un turno.

**Campos clave:**
- `id`, `rideId`, `passengerId`, `amountTotal`
- `status` (BookingStatus), `dispatchStatus` (BookingDispatchStatus)
- Timestamps de cada etapa: `driverAcceptedAt`, `driverArrivingAt`, `driverArrivedAt`, `passengerBoardedAt`, `tripStartedAt`, `tripCompletedAt`, `cancelledAt`
- `reportedNoShowAt`, `noShowNotes`
- Datos join del conductor: nombre, rating, foto, vehículo, contacto de emergencia
- Datos join del pasajero: nombre, rating, foto, vehículo

**Métodos de negocio:**
- `canPassengerConfirmBoarding` — true si dispatch es `accepted`, `driverArriving` o `driverArrived`
- `canDriverStartTrip` — true si dispatch es `passengerBoarded`
- `canDriverCompleteTrip` — true si dispatch es `inProgress` o `passengerBoarded`
- `dispatchLabel` — texto legible del estado actual

#### `user_profile.dart` — Modelo de Perfil

**Archivo:** `turno/lib/models/user_profile.dart`

**Campos clave:**
- Identidad: `id`, `fullName`, `universityId`, `campusId`
- Rol: `roleMode` (passenger/driver)
- Legal: `acceptedTerms`, `acceptedTermsAt`, `termsVersion`, `hasValidLicense`, `licenseCheckedAt`
- Seguridad: `strikesCount`, `suspendedUntil`, `vehicleSuspendedUntil`
- Contacto: `emergencyContact`, `safetyNotes`, `profilePhotoUrl`
- Rating: `ratingAvg` (default 5.0), `ratingCount`
- Vehículo: `vehicleBrand`, `vehicleModel`, `vehicleVersion`, `vehicleDoors`, `vehiclePlate`, `vehicleColor`
- `isDriverVerified`

**Métodos:**
- `copyWith` — patrón inmutable para crear copias modificadas
- `toJson` — serialización para upsert

#### `wallet.dart` — Modelo de Billetera

**Archivo:** `turno/lib/models/wallet.dart`

Simple: `userId`, `balanceAvailable` (CLP disponible), `balanceHeld` (CLP retenido en reservas activas), `updatedAt`.

**Getter:** `totalBalance = balanceAvailable + balanceHeld`

#### `transaction.dart` — Modelo de Transacción

**Archivo:** `turno/lib/models/transaction.dart`

Ledger inmutable: `id`, `userId`, `bookingId?`, `type` (TxType), `amount` (positivo=crédito, negativo=débito), `metadata` (JSON), `createdAt`.

**Getters:** `typeLabel` (texto legible), `isCredit` (amount > 0)

#### `user_review.dart`, `favorite_user.dart`, `legal_terms.dart`, `app_notification.dart`

Modelos auxiliares para reseñas, favoritos, términos legales y notificaciones in-app. Ver sección de funciones específicas.

### 5.5. Servicios — `services/`

Los servicios son la capa de comunicación con el backend. Cada uno instancia `SupabaseConfig.client` internamente y expone métodos de alto nivel.

#### `auth_service.dart` — Autenticación

| Método | Qué hace | Backend |
|--------|----------|---------|
| `signUp()` | Crea usuario con email/password + metadatos (nombre, términos, licencia, vehículo) | `supabase.auth.signUp()` |
| `signIn()` | Login con email/password | `supabase.auth.signInWithPassword()` |
| `signOut()` | Cierra sesión + limpia snapshots de notificaciones | `supabase.auth.signOut()` |
| `deleteMyAccount()` | Elimina cuenta permanentemente | Edge Function `delete-account` |

> El trigger DB `on_auth_user_created` automáticamente crea `users_profile` y `wallets` al registrarse.

#### `profile_service.dart` — Gestión de perfil

| Método | Qué hace |
|--------|----------|
| `saveBasicProfile()` | Upsert de datos básicos post-registro |
| `updateSafetyProfile()` | Actualiza contacto de emergencia, notas de seguridad |
| `updateProfileDetails()` | Actualiza nombre, foto, vehículo, licencia |
| `uploadProfilePhoto()` | Sube foto a Supabase Storage bucket `profile-photos` (JPG/PNG/WEBP) |
| `getProfile()` | Obtiene perfil del usuario actual |
| `getProfileById()` | Obtiene perfil de otro usuario (si tiene acceso RLS) |
| `setRoleMode()` | Cambia entre passenger/driver |

#### `ride_service.dart` — Gestión de turnos

| Método | Qué hace |
|--------|----------|
| `createRide()` | Inserta nuevo turno en DB |
| `cancelRide()` | Cancela turno (RPC `driver_cancel_ride`) — reembolsa pasajeros, evalúa strike |
| `searchRides()` | Busca turnos activos con filtros (campus, comuna, dirección, fecha). Excluye turnos del propio conductor |
| `getRideById()` | Obtiene detalle de un turno |
| `getMyRides()` | Obtiene todos los turnos publicados por el conductor actual |

#### `booking_service.dart` — Gestión de reservas

| Método | Qué hace |
|--------|----------|
| `createBooking(rideId)` | Reserva un turno (RPC `create_booking`) — valida UUID, disponibilidad, saldo |
| `confirmBoarding(bookingId)` | Pasajero confirma abordaje (RPC `confirm_boarding`) |
| `cancelBooking(bookingId)` | Pasajero cancela reserva (RPC `cancel_booking`) |
| `driverAcceptBooking()` | Conductor acepta reserva |
| `driverRejectBooking()` | Conductor rechaza reserva (con razón) |
| `driverMarkArriving()` | Conductor marca "en camino" |
| `driverMarkArrived()` | Conductor marca "llegó" |
| `driverStartTrip()` | Conductor inicia viaje |
| `driverCompleteTrip()` | Conductor finaliza viaje |
| `driverCompleteRide()` | Conductor finaliza todo el turno (todos los pasajeros) |
| `reportDriverNoShow()` | Pasajero reporta conductor ausente |
| `getMyBookings()` | Obtiene reservas del pasajero actual con joins (driver, ride, universidad, campus) |
| `getBookingsForMyRides()` | Obtiene todas las reservas de los turnos del conductor actual |

#### `wallet_service.dart` — Billetera

| Método | Qué hace |
|--------|----------|
| `getWallet()` | Obtiene saldo del usuario actual |
| `getTransactions()` | Obtiene historial de transacciones (últimas 30) |
| `createTopupIntent(amount)` | Crea intención de recarga vía Edge Function `create-topup-intent` |
| `sandboxTopup(amount)` | Recarga directa (modo sandbox/dev) vía RPC |
| `sandboxWithdraw(amount)` | Retiro directo (modo sandbox/dev) vía RPC |
| `ensureWalletExists()` | Crea wallet si no existe |

#### `withdrawal_service.dart` — Retiros

| Método | Qué hace |
|--------|----------|
| `requestWithdrawal(amount)` | Crea solicitud de retiro (mínimo $20.000) |
| `getWithdrawals()` | Historial de retiros del usuario |

#### `reference_data_service.dart` — Datos de referencia

Carga universidades y campus desde la DB con **fallback local** a las constantes hardcodeadas.

| Método | Qué hace |
|--------|----------|
| `getUniversities()` | Lista de universidades (DB o fallback) |
| `getUniversityById(id)` | Universidad específica |
| `getCampusesByUniversity(universityId)` | Campus de una universidad |
| `getCampusesWithUniversity()` | Todos los campus con nombre de universidad incluido |

**Flag:** `lastCallUsedFallback` — indica si se usó el fallback local (útil para mostrar warning al usuario).

#### `legal_service.dart` — Términos legales

Contenido estático de términos y condiciones. Devuelve `LegalTerms` con versión `v1.1-legal-strikes` y 8 bullets clave.

#### `review_service.dart` — Reseñas

| Método | Qué hace |
|--------|----------|
| `submitReview()` | Envía reseña (RPC `submit_booking_review`) |
| `getPublicUserReviews()` | Obtiene reseñas públicas de un usuario |
| `hasReviewForBooking()` | Verifica si ya dejó reseña en ese booking |

#### `favorites_service.dart` — Favoritos

| Método | Qué hace |
|--------|----------|
| `toggleFavorite()` | Toggle favorito (RPC `toggle_favorite_user`) |
| `getMyFavorites()` | Lista mis favoritos (RPC `list_my_favorites`) |
| `isFavorite()` | Verifica si un usuario es favorito |

#### `notification_service.dart` — Notificaciones locales

Singleton que usa `flutter_local_notifications`. Solo activo en iOS (web no soporta notificaciones locales). Muestra alertas nativas.

#### `push_notification_service.dart` — Push notifications

Singleton para iOS nativo. Usa `MethodChannel('cl.turnoapp/push')` para comunicarse con código nativo Swift/Obj-C. Registra el device token en la tabla `device_tokens` cuando el usuario se autentica.

#### `booking_notification_service.dart` — Notificaciones in-app por cambio de estado

Singleton que detecta **transiciones de estado** en bookings:

- **Para pasajeros:** notifica cuando el conductor acepta, está en camino, llegó, viaje en curso, completado, cancelado, no-show
- **Para conductores:** notifica nueva solicitud de reserva, aceptación, cancelación, pasajero a bordo, viaje finalizado

Mantiene un **snapshot** del estado anterior de cada booking y compara para detectar cambios. Dispara tanto notificaciones locales como notificaciones in-app (vía callback al `inAppNotificationProvider`).

### 5.6. Providers de Estado (Riverpod) — `providers/`

Riverpod se usa con el patrón **StateNotifier + StateNotifierProvider**. Cada provider encapsula estado + lógica de un dominio.

#### `service_providers.dart` — Providers de servicios

Expone cada servicio como un Riverpod `Provider`:

```dart
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final profileServiceProvider = Provider<ProfileService>((ref) => ProfileService());
final walletServiceProvider = Provider<WalletService>((ref) => WalletService());
final rideServiceProvider = Provider<RideService>((ref) => RideService());
final bookingServiceProvider = Provider<BookingService>((ref) => BookingService());
// ... etc
```

Esto permite que los notifiers accedan a los servicios vía `ref.read()`.

#### `home_provider.dart` — Estado del Home

**State:** `HomeState` con `profile?`, `wallet?`, `loading`, `switchingRole`, `errorMessage`

**Acciones:**
- `load()` — carga perfil + wallet en paralelo (`Future.wait`)
- `refresh()` — recarga
- `setRoleMode(mode)` — cambia rol del usuario

#### `wallet_provider.dart` — Estado de Billetera

**State:** `WalletState` con `wallet?`, `transactions[]`, `loading`, `topupLoading`

**Acciones:**
- `load()` — carga wallet + transacciones
- `createTopupIntent(amount)` — crea intención de recarga
- `sandboxTopup(amount)` — recarga sandbox
- `sandboxWithdraw(amount)` — retiro sandbox
- `requestWithdrawal(amount)` — solicita retiro

#### `search_rides_provider.dart` — Estado de Búsqueda

**State:** `SearchRidesState` con filtros (`selectedCommune`, `selectedDirection`, `selectedCampusId`, `selectedDate`), `campuses[]`, `results[]`, `loading`, `searched`

**Acciones:**
- `loadCampuses()` — carga lista de campus
- `search()` — ejecuta búsqueda con los filtros actuales
- `setCommune()`, `setDirection()`, `setCampus()`, `setDate()` — actualiza filtros
- `clearFilters()` — resetea todo

#### `my_rides_provider.dart` — Estado de Reservas del Pasajero

**State:** `MyRidesState` con `bookings[]`, `loading`

**Características especiales:**
- **Polling cada 5 segundos** (`Timer.periodic`) para datos en tiempo real
- Integra `BookingNotificationService` para notificaciones in-app
- Timeout de 15s en la carga para no bloquear

**Acciones:** `load()`, `confirmBoarding()`, `cancelBooking()`, `reportNoShow()`, acciones de conductor (`driverAcceptBooking()`, `driverMarkArriving()`, etc.)

#### `driver_rides_provider.dart` — Estado de Turnos del Conductor

**State:** `DriverRidesState` con `rides[]`, `bookings[]`, `loading`, `errorMessage`

**Características especiales:**
- **Polling cada 5 segundos** (`Timer.periodic`)
- Carga rides + bookings del conductor en paralelo
- Integra `BookingNotificationService`

**Acciones:** `load()`, `cancelRide()`, `acceptBooking()`, `rejectBooking()`, `markArriving()`, `markArrived()`, `startTrip()`, `completeTrip()`, `completeRide()`

#### `favorites_provider.dart` — Estado de Favoritos

**State:** `FavoritesState` con `favorites[]`, `loading`

**Acciones:** `load(roleFilter)`, `toggleFavorite()`, `isFavorite()`

#### `in_app_notification_provider.dart` — Estado de Notificaciones In-App

**State:** `InAppNotificationState` con `notifications[]` (máx 100), `unreadCount`

**Acciones:** `add()`, `markAsRead()`, `markAllAsRead()`, `clear()`

### 5.7. Features / Pantallas — `features/`

#### `auth/login_screen.dart` — Pantalla de Login

- Formulario email + password
- Usa `AuthService.signIn()`
- LoadingOverlay durante autenticación
- Links a: términos, privacidad, soporte, registro
- Al éxito: GoRouter redirect navega a `/home`

#### `auth/register_screen.dart` — Pantalla de Registro

- Campos: nombre completo, email, contraseña, universidad
- Toggle opcional "Registrarme como conductor" → despliega campos de vehículo (marca, modelo, versión, puertas, patente)
- Checkboxes obligatorios: aceptar términos + declarar licencia vigente
- Carga universidades desde `ReferenceDataService` (con fallback local)
- Llama `AuthService.signUp()` + `ProfileService.saveBasicProfile()` (best-effort)
- Links a términos y privacidad

#### `profile_switch/home_screen.dart` — Home Principal (Hub Central)

**La pantalla más importante de la app.** Usa `homeProvider`.

- **Card de switch de rol:** toggle animado entre pasajero y conductor
- **Validación de modo conductor:** al intentar cambiar a conductor, verifica:
  - Términos aceptados
  - Licencia vigente declarada
  - Datos de vehículo completos (marca, modelo, versión, puertas, patente)
  - No estar suspendido
  - Si faltan datos de vehículo → muestra modal bottom sheet para completarlos
- **Card de billetera:** muestra `balanceAvailable`, link a `/wallet`
- **Estado de seguridad:** muestra strikes y suspensiones si existen
- **Botones de acción contextuales:**
  - Modo conductor: "Publicar turno" → `/publish`, "Mis turnos publicados" → `/driver-rides`
  - Modo pasajero: "Buscar turno" → `/search`, "Mis reservas" → `/my-rides`
- **Links secundarios:** términos, favoritos, privacidad, soporte, botón de pánico
- Pull-to-refresh con animación fade

#### `rides_publish/publish_ride_screen.dart` — Publicar Turno

- Formulario: dirección (hacia/desde campus), comuna de origen, universidad, campus, punto de encuentro, toggle radial, selector de fecha/hora, stepper de cantidad de asientos
- Carga universidades/campuses desde DB (fallback local)
- Calcula pricing automáticamente
- Valida: términos aceptados, licencia válida, hora futura
- Crea turno vía `RideService.createRide()` → pop al éxito

#### `rides_search/search_rides_screen.dart` — Buscar Turnos

- Usa `searchRidesProvider`
- Filtros: comuna, dirección, campus (cargado dinámicamente), fecha
- Búsqueda automática al cambiar filtros
- Resultados renderizados con `TurnoCard`
- Tap en card → navega a `/booking/{rideId}`

#### `booking/booking_screen.dart` — Detalle y Reserva

- Carga en paralelo: detalle del turno, saldo del pasajero, perfil del conductor, reseñas del conductor, estado de favorito
- Muestra: info del turno, perfil del conductor con rating y reseñas, desglose de pago (precio asiento + fee = total)
- Verifica saldo suficiente antes de permitir reservar
- Diálogo de confirmación explica el flujo de retención de fondos
- Llama `BookingService.createBooking()` → navega a `/my-rides`
- Toggle de favorito del conductor

#### `my_rides/my_rides_screen.dart` — Reservas del Pasajero

- Tabs: "Activas" / "Historial" (via `TabController`)
- Usa `myRidesProvider`
- Acciones por reserva: confirmar abordaje, cancelar, reportar no-show (con validación de 10 min), reseñar conductor, favorito
- Auto-navega a `/arrival` cuando detecta un viaje completado
- Cada card muestra: estado, dispatch status, info del conductor, precio

#### `my_rides/active_trip_screen.dart` — Seguimiento en Vivo (Pasajero)

- **Polling cada 5 segundos**
- Timeline visual de 7 pasos: reserved → accepted → driver arriving → driver arrived → boarded → in progress → completed
- Muestra: nombre del conductor, vehículo, contacto de emergencia, rating
- Acciones: confirmar abordaje, favorito, reseñar, botón de emergencia
- Auto-navega a `/arrival` al completar

#### `my_rides/driver_rides_screen.dart` — Turnos del Conductor

- Tabs: "Mis turnos" / "Pasajeros"
- Usa `driverRidesProvider`
- Tab 1: lista de turnos activos e históricos, con botones de cancelar/completar/gestionar
- Tab 2: todas las reservas de pasajeros con badge de pendientes
- Acciones por booking: aceptar, rechazar (con razón), marcar en camino/llegó, iniciar viaje, completar viaje, reseñar pasajero, favorito
- Usa widget `BookingFlowButtons`

#### `my_rides/driver_active_ride_screen.dart` — Gestión de Turno Activo

- **Polling cada 5 segundos**
- Vista detallada de un turno específico
- Header con info del turno + tracker de progreso (aceptados/abordados/completados)
- Acciones a nivel de turno: "Iniciar viaje para todos", "Finalizar turno", "Cancelar turno"
- Lista de pasajeros con su estado individual de dispatch (color/icono)
- Usa `BookingFlowButtons` por pasajero
- Auto-navega a `/arrival` al completar

#### `my_rides/arrival_screen.dart` — Llegada a Destino

- Pantalla de celebración simple: ícono check, "¡Llegaste a destino!", botón "Volver al inicio"
- Stateless, sin servicios

#### `wallet/wallet_screen.dart` — Billetera

- Usa `walletProvider`
- Card de saldo con gradiente
- **Recarga:** bottom sheet con montos rápidos (`[2000, 4000, 6000, 10000, 20000]`), input custom, llama `sandboxTopup()`
- **Retiro:** dialog con input de monto, valida mínimo $20.000, llama `sandboxWithdraw()`
- Historial de transacciones con íconos de crédito/débito

#### `favorites/favorites_screen.dart` — Favoritos

- Usa `favoritesProvider`
- Filter chips: Todos / Conductores / Pasajeros
- Cards con avatar, nombre, rol, rating, vehículo

#### `notifications/notifications_screen.dart` — Notificaciones In-App

- Lista de notificaciones desde `inAppNotificationProvider`
- Marca todas como leídas al abrir
- No leídas destacadas con punto azul y fondo diferente

#### `profile/edit_profile_screen.dart` — Editar Perfil

- Carga perfil actual
- Campos: nombre completo, foto (cámara/galería via `ImagePicker`), contacto de emergencia, notas de seguridad, datos de vehículo (marca, modelo, versión, puertas, patente, color), toggle de licencia
- Upload de foto: selecciona localmente → sube a Supabase Storage al guardar
- Eliminación de cuenta: diálogo con razón → llama `AuthService.deleteMyAccount()`

#### `legal/terms_screen.dart`, `legal/privacy_policy_screen.dart`, `legal/support_screen.dart`

Pantallas de contenido estático:
- **Términos:** bullets del `LegalService`, escudo legal, links a privacidad/soporte
- **Privacidad:** 5 secciones (datos recopilados, uso, compartimiento, retención, contacto)
- **Soporte:** email (mailto:), llamada de emergencia (tel:133), tiempo de respuesta

### 5.8. Widgets Compartidos — `shared/widgets/`

| Widget | Archivo | Qué hace |
|--------|---------|----------|
| `AppSnackbar` | `app_snackbar.dart` | Muestra SnackBar estilizado (éxito/error, 3s, floating) |
| `DecorativeBackground` | `decorative_background.dart` | Fondo con gradiente oscuro + blobs radiales decorativos + línea horizontal |
| `LoadingOverlay` | `loading_overlay.dart` | Overlay semitransparente con spinner centrado + mensaje opcional |
| `TurnoCard` | `turno_card.dart` | Card principal de turno: dirección, ruta, precio, fecha, asientos, universidad, conductor, punto de encuentro |
| `BookingFlowButtons` | `booking_flow_buttons.dart` | Barra de botones contextuales según `dispatchStatus`: aceptar/rechazar, en camino, llegué, iniciar viaje, finalizar viaje + review + favorito |
| `ReviewDialog` | `review_dialog.dart` | AlertDialog con selector de estrellas (1-5) + comentario opcional (máx 500 chars) |
| `RideTimeStatus` | `ride_time_status.dart` | Badge de tiempo relativo: pasado=gris, ≤5min=verde, ≤15min=verde, <24h=azul, >24h=azul con fecha |

---

## 6. BACKEND — SUPABASE

### 6.1. PostgreSQL — Esquema Completo

#### Enumeraciones

| Enum | Valores |
|------|---------|
| `role_mode` | `'passenger'`, `'driver'` |
| `ride_direction` | `'to_campus'`, `'from_campus'` |
| `booking_status` | `'reserved'`, `'cancelled'`, `'completed'`, `'no_show'` |
| `tx_type` | `'topup'`, `'booking_hold'`, `'release_to_driver'`, `'platform_fee'`, `'refund'`, `'withdrawal_request'`, `'withdrawal_paid'`, `'penalty'` |
| `booking_dispatch_status` | `'reserved'`, `'accepted'`, `'driver_arriving'`, `'driver_arrived'`, `'passenger_boarded'`, `'in_progress'`, `'completed'`, `'cancelled'`, `'no_show'` |

#### Tablas

**`universities`** — Catálogo de universidades
- `id` (uuid PK), `code` (text UNIQUE), `name` (text)
- RLS: lectura pública

**`campuses`** — Catálogo de campus
- `id` (uuid PK), `university_id` (uuid FK→universities), `name` (text), `commune` (text)
- RLS: lectura pública

**`users_profile`** — Perfil extendido del usuario (1:1 con auth.users)
- `id` (uuid PK, FK→auth.users), `full_name`, `university_id` (FK), `campus_id` (FK)
- `role_mode` (enum), `is_driver_verified`, `strikes_count`, `suspended_until`
- `accepted_terms`, `accepted_terms_at`, `terms_version`
- `has_valid_license`, `license_checked_at`
- `emergency_contact`, `safety_notes`, `profile_photo_url`
- `rating_avg` (numeric 3,2, default 5.00), `rating_count`
- `vehicle_suspended_until`
- `vehicle_model`, `vehicle_brand`, `vehicle_version`, `vehicle_doors`, `vehicle_plate`, `vehicle_color`
- `created_at`
- **Check constraints:**
  - `vehicle_doors` entre 2 y 6 (o null)
  - **Si `role_mode = 'driver'`:** debe tener licencia válida + marca + modelo + versión + puertas + patente (NOT VALID — se aplica a nuevas filas)

**`wallets`** — Billetera del usuario (1:1 con users_profile)
- `user_id` (uuid PK, FK→users_profile), `balance_available` (int, ≥0), `balance_held` (int, ≥0), `updated_at`
- Escritura solo vía RPCs SECURITY DEFINER

**`rides`** — Turnos publicados
- `id` (uuid PK), `driver_id` (FK→users_profile), `university_id` (FK), `campus_id` (FK)
- `origin_commune` (text, check: en lista de comunas permitidas)
- `direction` (enum), `departure_at` (timestamp sin timezone — hora local Chile)
- `seat_price` (int, **= 2000** fijo), `platform_fee` (int, **= 190** fijo), `driver_net_amount` (int, **= 2000** fijo)
- `seats_total` (int, >0), `seats_available` (int, ≥0, ≤seats_total)
- `status` (text: active/cancelled/completed)
- `meeting_point`, `is_radial` (bool, solo válido si comuna = Chicoreo)
- `cancel_reason`, `cancelled_at`, `created_at`
- **Check constraints:** precio fijo, radial solo en Chicoreo

**`bookings`** — Reservas
- `id` (uuid PK), `ride_id` (FK→rides), `passenger_id` (FK→users_profile)
- `amount_total` (int), `status` (enum), `dispatch_status` (enum)
- Timestamps por etapa: `confirmed_at`, `driver_accepted_at`, `driver_arriving_at`, `driver_arrived_at`, `passenger_boarded_at`, `trip_started_at`, `trip_completed_at`, `cancelled_at`
- `cancelled_by` (FK→users_profile), `cancel_reason`
- `reported_no_show_at`, `no_show_notes`
- `created_at`
- **Índice único parcial:** `(ride_id, passenger_id)` WHERE `status = 'reserved'` (evita doble reserva)

**`transactions`** — Ledger inmutable
- `id` (uuid PK), `user_id` (FK), `booking_id` (FK, nullable), `type` (enum), `amount` (int), `metadata` (jsonb), `created_at`
- **Reglas de inmutabilidad:** ON UPDATE DO INSTEAD NOTHING, ON DELETE DO INSTEAD NOTHING
- Solo lectura para el usuario dueño, escritura solo vía RPCs

**`withdrawals`** — Solicitudes de retiro
- `id` (uuid PK), `driver_id` (FK), `amount` (int, ≥20000), `status` (requested/processing/paid/rejected), `requested_at`, `processed_at`

**`strikes`** — Faltas del conductor
- `id` (uuid PK), `driver_id` (FK), `reason` (text), `booking_id` (FK, nullable), `created_at`, `expires_at`, `source`

**`fintoc_payments`** — Pagos procesados por Fintoc (idempotencia)
- `checkout_session_id` (text PK), `user_id` (FK), `amount` (int), `status`, `amount_requested`, `fee_amount`, `amount_charged`, `currency`, `created_at`

**`booking_events`** — Auditoría de cambios de despacho
- `id` (uuid PK), `booking_id` (FK), `ride_id` (FK), `actor_user_id` (FK), `actor_role`, `from_status`, `to_status`, `event_type`, `metadata` (jsonb), `created_at`

**`booking_reviews`** — Reseñas
- `id` (uuid PK), `booking_id` (FK), `ride_id` (FK), `reviewer_id` (FK), `reviewee_id` (FK)
- `reviewer_role`, `reviewee_role`, `stars` (1-5), `comment` (máx 500 chars), `is_public`, `created_at`
- **Unique:** `(booking_id, reviewer_id)` — una reseña por persona por booking
- **Check:** `reviewer_id ≠ reviewee_id`

**`user_favorites`** — Favoritos entre usuarios
- `(user_id, favorite_user_id)` (PK compuesta, ambos FK→users_profile)
- `source` (default 'manual'), `created_at`
- **Check:** `user_id ≠ favorite_user_id` (no se puede favoritar a sí mismo)

**`device_tokens`** — Tokens de push notification
- `id` (uuid PK), `user_id` (FK), `platform` (ios/android), `token` (text), `created_at`, `updated_at`
- **Unique:** `(user_id, token)`

### 6.2. Row Level Security (RLS)

RLS está habilitado en **todas** las tablas sensibles. Políticas clave:

| Tabla | Política | Condición |
|-------|----------|-----------|
| `users_profile` | `profile_self_rw` | ALL para el propio usuario (`auth.uid() = id`) |
| `users_profile` | `profile_driver_passenger_read` | SELECT si el usuario es conductor con booking donde este perfil es pasajero |
| `users_profile` | `profile_active_driver_read` | SELECT si este perfil es conductor de un ride activo |
| `wallets` | `wallet_self_read` | SELECT solo para el dueño |
| `rides` | `rides_public_read` | SELECT para todos los autenticados |
| `rides` | `rides_driver_insert` | INSERT si `auth.uid() = driver_id` Y tiene términos + licencia Y no está baneado Y departure > ahora |
| `bookings` | `bookings_self_read` | SELECT si pasajero O conductor del ride |
| `transactions` | `tx_self_read` | SELECT si `auth.uid() = user_id` |
| `withdrawals` | `withdrawals_driver_rw` | ALL para el dueño |
| `strikes` | `strikes_driver_read` | SELECT si `auth.uid() = driver_id` |
| `fintoc_payments` | `fintoc_payments_self_read` | SELECT si `auth.uid() = user_id` |
| `booking_events` | `booking_events_participant_read` | SELECT si actor, pasajero o conductor |
| `booking_reviews` | `booking_reviews_public_read` | SELECT si is_public O reviewer O reviewee |
| `user_favorites` | owner_read/insert/delete | ALL para el dueño |
| `universities` | `universities_public_read` | SELECT para todos |
| `campuses` | `campuses_public_read` | SELECT para todos |

### 6.3. Funciones RPC

#### Flujo de Reserva (authenticated)

| RPC | Params | Lógica |
|-----|--------|--------|
| `create_booking(p_ride_id)` | uuid → uuid | Bloquea ride, verifica disponibilidad/auth/saldo/overlaps, deduce wallet (seat_price + platform_fee), crea booking + transaction + event |
| `confirm_boarding(p_booking_id)` | uuid → void | Pasajero confirma abordaje → dispatch `passenger_boarded`, log event |
| `cancel_booking(p_booking_id)` | uuid → void | Pasajero cancela (antes de trip started + dentro de 10min de departure), refund, log event |

#### Flujo de Despacho (conductor)

| RPC | Params | Lógica |
|-----|--------|--------|
| `driver_accept_booking(p_booking_id)` | uuid → void | reserved → accepted |
| `driver_mark_arriving(p_booking_id)` | uuid → void | accepted → driver_arriving |
| `driver_mark_arrived(p_booking_id)` | uuid → void | driver_arriving → driver_arrived |
| `driver_start_trip(p_booking_id)` | uuid → void | passenger_boarded → in_progress |
| `driver_complete_trip(p_booking_id)` | uuid → void | in_progress → completed, libera fondos al conductor (net), registra fee |
| `driver_reject_booking(p_booking_id, p_reason)` | uuid, text → void | Refund al pasajero |
| `driver_cancel_ride(p_ride_id, p_reason)` | uuid, text → void | Cancela todo el ride, refund a todos los pasajeros, strike si <2h |
| `passenger_report_no_show(p_booking_id, p_notes)` | uuid, text → void | Reporta conductor ausente (ventana 10min-12h), refund, strike al conductor |
| `complete_ride_manual(p_ride_id)` | uuid → void | Completa todos los bookings del ride de una vez, con accounting correcto |

#### Pagos / Billetera

| RPC | Params | Lógica |
|-----|--------|--------|
| `credit_wallet_topup(...)` | user_id, amount, checkout_session_id, amount_charged, fee_amount, provider → void | Idempotente: registra fintoc_payment, acredita wallet, escribe ledger |
| `sandbox_topup(p_amount)` | int → void | Dev-only: agrega saldo directo (máx 200,000) |
| `sandbox_withdraw(p_amount)` | int → void | Dev-only: crea withdrawal directo (mín 20,000) |

#### Reseñas y Favoritos

| RPC | Params | Lógica |
|-----|--------|--------|
| `submit_booking_review(p_booking_id, p_stars, p_comment)` | uuid, int, text → uuid | Reseña en trip completado (ventana 30 días), una por reviewer, recalcula rating |
| `toggle_favorite_user(p_target_user_id)` | uuid → bool | Toggle favorito |
| `list_my_favorites(p_role_filter, p_limit)` | text, int → table | Lista favoritos con info de perfil |
| `get_public_user_reviews(p_user_id, p_limit)` | uuid, int → table | Reseñas públicas de un usuario |

#### Helpers de Despacho

| RPC | Params | Lógica |
|-----|--------|--------|
| `log_booking_event(...)` | varios → void | Inserta row en booking_events (audit log) |
| `check_no_overlapping_booking(...)` | uuid, timestamp, uuid → bool | Verifica que no haya booking reservado dentro de ±10min |
| `expire_stale_bookings()` | — → int | Marca bookings como no_show después de departure+15min |
| `expire_stale_bookings_and_release()` | — → int | Igual que arriba + refund + restaura asiento |
| `set_ride_completed_if_no_open_bookings(p_ride_id)` | uuid → void | Marca ride como completado si partió o todos los bookings están cerrados |
| `expire_past_active_rides()` | — → int | Completa en batch todos los rides activos pasados |

#### Strikes y Compliance

| RPC | Params | Lógica |
|-----|--------|--------|
| `refresh_user_strike_state(p_driver_id)` | uuid → void | Recalcula strikes_count, suspended_until desde strikes activos (no expirados) |
| `is_driver_banned_now(p_driver_id)` | uuid → bool | Refresh strike state + retorna si está suspendido |

#### Zona Horaria Chile

| RPC | Lógica |
|-----|--------|
| `current_chile_time()` | Retorna `timezone('America/Santiago', now())` |
| `get_chile_timezone_offset()` | Retorna offset UTC actual |

#### Diagnóstico

| RPC | Lógica |
|-----|--------|
| `reference_access_diag()` | Counts de universities/campuses, UID actual, rol JWT |
| `wallet_reconciliation_diag(p_user_id)` | Compara wallet balances vs. esperado desde transacciones + bookings activos |

#### Gestión de Cuenta

| RPC | Lógica |
|-----|--------|
| `delete_user_account()` | Elimina TODO: bookings, rides, transactions, withdrawals, fintoc_payments, strikes, wallet, profile, auth.user |

### 6.4. Triggers

| Trigger | Tabla | Timing | Función | Propósito |
|---------|-------|--------|---------|-----------|
| `on_auth_user_created` | `auth.users` | AFTER INSERT | `handle_new_user()` | Auto-crea `users_profile` y `wallets` al registrarse |
| `trg_enforce_ride_pricing` | `rides` | BEFORE INSERT/UPDATE | `enforce_ride_pricing()` | Ajusta precio/fee/net según universidad |
| `trg_compute_ride_pricing` | `rides` | BEFORE INSERT/UPDATE OF seat_price | `trg_compute_ride_pricing()` | Fuerza seat_price=2000, platform_fee=190, driver_net_amount=2000 |
| `trg_validate_ride_departure` | `rides` | BEFORE INSERT/UPDATE OF departure_at | `trg_validate_ride_departure()` | Rechaza rides con departure_at <= hora actual Chile |
| `trg_refresh_user_strike_state` | `strikes` | AFTER INSERT/UPDATE/DELETE | `trg_refresh_user_strike_state()` | Recalcula automáticamente strike count y suspensión del conductor |
| `booking_event_push_trigger` | `booking_events` | AFTER INSERT | `trg_booking_event_push()` | Dispara push notification vía pg_net |

### 6.5. Índices

Los índices están optimizados para las consultas más frecuentes:

| Índice | Tabla | Columnas | Parcial |
|--------|-------|----------|---------|
| `idx_rides_search` | rides | departure_at, campus_id, direction, status | — |
| `idx_rides_driver` | rides | driver_id, created_at desc | — |
| `idx_rides_active_departure_campus_direction` | rides | departure_at, campus_id, direction | WHERE status='active' |
| `idx_bookings_passenger` | bookings | passenger_id, created_at desc | — |
| `idx_bookings_ride` | bookings | ride_id, status | — |
| `idx_bookings_dispatch_status` | bookings | dispatch_status, created_at desc | — |
| `idx_bookings_unique_active_passenger_ride` | bookings | ride_id, passenger_id | WHERE status='reserved' (UNIQUE) |
| `idx_transactions_user_type_created` | transactions | user_id, type, created_at desc | — |
| `idx_booking_events_booking_created` | booking_events | booking_id, created_at desc | — |
| `idx_booking_reviews_reviewee_created` | booking_reviews | reviewee_id, created_at desc | — |
| `idx_user_favorites_user_created` | user_favorites | user_id, created_at desc | — |
| `idx_device_tokens_user_id` | device_tokens | user_id | — |

### 6.6. Reglas de Inmutabilidad (Ledger)

La tabla `transactions` es **append-only**:
- `transactions_no_update` rule: ON UPDATE DO INSTEAD NOTHING
- `transactions_no_delete` rule: ON DELETE DO INSTEAD NOTHING

Esto garantiza que el ledger financiero es **auditable e inmutable**. Ningún usuario (ni siquiera admin) puede modificar transacciones existentes.

### 6.7. Vistas Operativas

**`ops_daily_metrics`** — Métricas diarias rolling de 30 días:
- Rides creados por día
- Bookings por status
- Topups (count y amount)
- Strikes emitidos
- Usa `generate_series` para generar la serie de fechas

### 6.8. Evolución del Esquema (27 Migraciones)

Cada migración es un archivo SQL versionado que se aplica secuencialmente:

| # | Archivo | Qué agregó |
|---|---------|-----------|
| 00 | `_schema.sql` | Esquema base: 9 tablas, 5 enums, índices, reglas de ledger inmutable |
| 01 | `_rls.sql` | Políticas RLS en tablas sensibles |
| 02 | `_functions.sql` | RPCs core: create_booking, confirm_boarding, cancel_booking |
| 03 | `_auth_trigger.sql` | Trigger que crea perfil + wallet automáticamente al registrarse |
| 04 | `_seed.sql` | 6 universidades + ~23 campus con UUIDs fijos |
| 05 | `_webhook_rpc.sql` | RPC credit_wallet_topup para webhook de pagos |
| 06 | `_public_grants.sql` | GRANT SELECT en universities/campuses para rol anon |
| 07 | `_reference_rls.sql` | RLS + política de lectura pública en universities/campuses |
| 08 | `_reference_diag.sql` | RPC de diagnóstico de acceso a referencias |
| 09 | `_compliance_pricing_strikes.sql` | Sistema de strikes, compliance, pricing trigger, campos de licencia/términos |
| 10 | `_profile_photos_storage.sql` | Bucket Storage para fotos de perfil |
| 11 | `_driver_vehicle_required.sql` | Constraint: conductor debe tener datos de vehículo |
| 12 | `_beta_observability_scalability.sql` | Índices parciales, vista ops_daily_metrics, RPC wallet_reconciliation_diag |
| 13 | `_launch_pricing_stripe_ready.sql` | Fee fijo CLP 190, credit_wallet_topup con fee tracking |
| 14 | `_dispatch_hardening.sql` | Máquina de despacho completa: booking_dispatch_status enum, booking_events table, 7 RPCs de dispatch, fix de double-fee bug |
| 15 | `_wallet_reconciliation_adjustment.sql` | Ajuste one-time de conciliación wallet/ledger |
| 16 | `_reviews_favorites.sql` | Tablas booking_reviews + user_favorites, RPCs asociados |
| 17 | `_strikes_reconciliation_and_guardrails.sql` | Rebuild de strike counters desde expires_at, trigger refresh_user_strike_state |
| 18 | `_chile_local_ride_times.sql` | departure_at como timestamp sin timezone (hora Chile), helper current_chile_time() |
| 19 | `_pricing_and_double_booking_guard.sql` | Pricing fijo 2000/190/2000, guard anti-overlap de bookings |
| 20 | `_auto_expire_stale_bookings.sql` | Expiración automática bookings stale (departure+15min), pg_cron job |
| 21 | `_complete_ride_manual.sql` | RPC para que conductor complete viaje sin confirmación de pasajero (versión inicial buggy) |
| 22 | `_hardening_close_gaps.sql` | sandbox_topup, sandbox_withdraw, delete_user_account, fix complete_ride_manual |
| 23 | `_restore_dispatch_event_logging.sql` | Restaura llamadas log_booking_event que se perdieron en migración 18 |
| 24 | `_push_notifications.sql` | device_tokens table, push_notify_dispatch_change via pg_net, trigger en booking_events |
| 25 | `_campus_carroceria_pricing_overlap.sql` | Drop vehicle_body_type, fix pricing (pasajero paga 2190), overlap reducido a ±10min |
| 26 | `_bookings_driver_id_for_realtime.sql` | Agrega driver_id en bookings para canales realtime eficientes |
| 27 | `_fintoc_payments.sql` | Tabla fintoc_payments, actualiza credit_wallet_topup y delete_user_account |
| 28 | `_fix_strikes_double_count.sql` | Fix conteo doble de strikes + auto-expire |
| 29 | `_adversarial_audit_fixes.sql` | Fixes de auditoría adversarial |
| 30 | `_security_hardening.sql` | Endurecimiento de seguridad |
| 31 | `_ugc_reporting_and_blocking.sql` | Reporte de contenido y bloqueo de usuarios |
| 32 | `_push_secret_config_table.sql` | Secret de push vía tabla de configuración |
| 33 | `_fintoc_sandbox_readiness.sql` | payment_intent_id, credit_wallet_topup pending→approved, update_fintoc_payment_status |

---

## 7. EDGE FUNCTIONS (DENO + TYPESCRIPT)

### `create-topup-intent` — Crear sesión de pago Fintoc

**Archivo:** `supabase/functions/create-topup-intent/index.ts`

**Propósito:** Crea una Checkout Session en Fintoc y retorna la `redirect_url` para que el usuario pague.

**Flujo:**
1. Autentica usuario vía JWT
2. Valida monto (2,000–200,000 CLP)
3. Calcula fee del 1% (`amount_charged = amount_requested + fee`)
4. Sanitiza `success_url`/`cancel_url` del cliente (solo `turnoapp://` u origin de `APP_BASE_URL`)
5. POST a `https://api.fintoc.com/v2/checkout_sessions` (header `Authorization` = secret key, sin Bearer) con `metadata: { user_id, amount_requested }` + `line_items`
6. INSERT `fintoc_payments` con `status=pending` (tracking de ciclo de vida)
7. Retorna `redirect_url` — el usuario paga en la página hosteada por Fintoc

Si `PAYMENT_PROVIDER=disabled`, retorna mensaje de deshabilitado.

**Variables de entorno:** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `FINTOC_SECRET_KEY`, `APP_BASE_URL`

### `fintoc-webhook` — Webhook de Fintoc

**Archivo:** `supabase/functions/fintoc-webhook/index.ts`

**Propósito:** Recibe eventos de Fintoc y acredita la billetera cuando el pago es exitoso.

**Eventos manejados:**
| Evento | Acción |
|--------|--------|
| `checkout_session.finished` (pi.status=succeeded) | `credit_wallet_topup` → pending→approved + acredita wallet |
| `checkout_session.finished` (pi.status=failed) | marca `fintoc_payments.status=failed` |
| `checkout_session.expired` | marca `expired` |
| `payment_intent.succeeded` | acredita vía `payment_intent_id` correlacionado |
| `payment_intent.failed` / `payment_intent.rejected` | actualiza estado a `failed` |

**Flujo:**
1. Verifica firma HMAC-SHA256 del header `Fintoc-Signature` (formato `t=<ts>,v1=<sig>` separado por comas, ventana 5 min)
2. Resuelve el pago desde `fintoc_payments` (monto autoritativo; fallback a metadata)
3. Idempotencia contra `fintoc_payments` por `checkout_session_id` (status approved = no-op)
4. Llama RPC `credit_wallet_topup` con provider `fintoc`

**Variables:** `FINTOC_WEBHOOK_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

### `send-push-notification` — Push APNs

**Archivo:** `supabase/functions/send-push-notification/index.ts`

**Propósito:** Envía notificaciones push a dispositivos iOS vía APNs.

**Flujo:**
1. Valida `X-Internal-Secret` header
2. Busca device tokens del usuario en `device_tokens` table
3. Para cada token: envía POST a `api.push.apple.com/3/device/<token>`
4. Si 410 (token expirado) → elimina token de la DB
5. JWT ES256 con caching de 50 min

**Variables:** `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_KEY_BASE64`, `INTERNAL_PUSH_SECRET`

### `delete-account` — Eliminar cuenta

**Archivo:** `supabase/functions/delete-account/index.ts`

**Propósito:** Hard delete de la cuenta del usuario (requerido por políticas de Apple App Store).

**Flujo:**
1. Autentica vía JWT
2. Llama `supabaseAdmin.auth.admin.deleteUser(userId, true)` con flag de hard delete

---

## 8. REALTIME — CANALES SUPABASE

La app utiliza **5 canales de Supabase Realtime** que escuchan cambios en PostgreSQL y actualizan el estado instantáneamente:

| Canal | Tabla | Filtro | Provider |
|-------|-------|--------|----------|
| `rides-driver-$uid` | `rides` | `driver_id` | `driver_rides_provider` |
| `bookings-driver-$uid` | `bookings` | `driver_id` | `driver_rides_provider` |
| `bookings-passenger-$uid` | `bookings` | `passenger_id` | `my_rides_provider` |
| `wallet-$uid` | `wallets` | `user_id` | `wallet_provider` (patch local instantáneo) |
| `home-wallet-$uid` + `profile-$uid` | `wallets` + `users_profile` | `user_id` / `id` | `home_provider` |

**Funcionamiento:**
- Cada canal escucha eventos `INSERT`, `UPDATE`, `DELETE` en su tabla
- Debounce de 600ms para evitar refrescos excesivos
- `wallet_provider` aplica **patch local** directo (parsea el payload y actualiza el estado sin re-fetch)
- Los demás providers re-fetchean los datos completos al detectar cambios
- Fallback: polling silencioso cada 45s por si se pierde la conexión WebSocket

---

## 9. STORAGE — FOTOS DE PERFIL

**Estructura de paths:** `{user_id}/avatar.{jpg|png|webp}`

**Políticas RLS del bucket:**
- **Read:** público (cualquiera puede ver)
- **Insert:** autenticado, path debe empezar con su UUID
- **Update:** autenticado, path debe empezar con su UUID
- **Delete:** autenticado, path debe empezar con su UUID

---

## 10. SISTEMA DE PAGOS

### Flujo de recarga con Fintoc (sandbox/test)

```
Usuario → WalletScreen → selecciona monto → createTopupIntent(amount)
                                                ↓
                                     Edge Function: create-topup-intent
                                     - valida monto (2.000–200.000)
                                     - fee 1% → amount_charged
                                                ↓
                                     Fintoc API: POST /v2/checkout_sessions
                                     Metadata: { user_id, amount_requested }
                                     fintoc_payments: INSERT status=pending
                                                ↓
                                     Retorna redirect_url
                                                ↓
                                     Usuario paga en página Fintoc (modo test)
                                                ↓
                                     Fintoc redirige a turnoapp://wallet?topup=success
                                                ↓
                                     Fintoc envía webhooks → fintoc-webhook
                                     - checkout_session.finished (pi.status=succeeded)
                                     - payment_intent.succeeded
                                                ↓
                                     Verifica firma Fintoc-Signature + idempotencia
                                                ↓
                                     RPC credit_wallet_topup (pending → approved)
                                                ↓
                                     Wallet balance_available += amount
                                     fintoc_payments: status=approved, payment_intent_id
                                     Transaction ledger: type=topup
```

> **Keys pendientes y pasos de configuración:** ver [`FINTOC_SETUP.md`](FINTOC_SETUP.md).

### Flujo de retiro

```
Usuario → WalletScreen → solicita retiro → sandboxWithdraw(amount)
                                                ↓
                                     RPC sandbox_withdraw
                                                ↓
                                     Wallet balance_available -= amount
                                     Withdrawal: status=requested
                                     Transaction ledger: type=withdrawal_request
```

### Flujo financiero de un viaje

```
1. RESERVA (create_booking RPC):
   Pasajero wallet: balance_available -= 2190, balance_held += 2190
   Transaction: type=bookingHold, amount=-2190

2. CONFIRMACIÓN DE ABORDAJE (confirm_boarding RPC):
   dispatch → passenger_boarded (solo cambia estado)

3. COMPLETAR VIAJE (driver_complete_trip RPC):
   Pasajero wallet: balance_held -= 2190
   Conductor wallet: balance_available += 2000
   Transaction pasajero: type=release_to_driver (implicit via held release)
   Transaction conductor: type=release_to_driver, amount=+2000
   Transaction plataforma: type=platform_fee, amount=+190

4. CANCELACIÓN (cancel_booking RPC):
   Pasajero wallet: balance_held -= amount, balance_available += amount
   Transaction: type=refund, amount=+amount
```

---

## 11. MOTOR DE NEGOCIO Y REGLAS

### Pricing (actual, migración 25)

| Concepto | Valor |
|----------|-------|
| Precio por asiento PUC/UCH | $2.500 CLP |
| Precio por asiento otras | $2.000 CLP |
| Comisión de plataforma | $190 CLP fijo (enforced por DB) |
| Lo que paga pasajero PUC/UCH | $2.690 CLP |
| Lo que paga pasajero otras | $2.190 CLP |
| Fee de recarga | 1% del monto solicitado |

### Reglas de publicación de turno

- El conductor debe tener: términos aceptados + licencia vigente + no suspendido
- El departure_at debe ser **futuro** (hora Chile)
- La comuna de origen debe estar en la lista permitida
- Si `is_radial = true`, la comuna debe ser **Chicoreo**
- El pricing es **forzado por trigger DB** (no importa lo que envíe el frontend)

### Reglas de reserva

- No puedes reservar tu propio turno
- No puedes tener reservas overlapping (dentro de ±10 minutos)
- Debes tener saldo suficiente (seat_price + platform_fee)
- El turno debe estar activo con asientos disponibles

### Reglas de cancelación

- **Pasajero:** puede cancelar antes de que el viaje inicie (dentro de ventana válida)
- **Conductor:** puede cancelar el turno completo (reembolsa a todos los pasajeros)
  - Si cancela <2h antes de departure → recibe strike
- **Auto-expiración:** bookings no abordados después de departure+15min → auto no-show + refund

---

## 12. SISTEMA DE DESPACHO — MÁQUINA DE ESTADOS

La máquina de estados de dispatch controla el ciclo de vida de cada reserva individual:

```
                    ┌─────────────────────────────────┐
                    │                                 │
                    ▼                                 │
┌──────────┐   ┌──────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐   ┌────────────┐   ┌───────────┐
│ reserved │──▶│ accepted │──▶│driver_arriving│──▶│driver_arrived│──▶│passenger_boarded │──▶│ in_progress│──▶│ completed │
└──────────┘   └──────────┘   └──────────────┘   └──────────────┘   └──────────────────┘   └────────────┘   └───────────┘
     │               │                                                                             │
     │               │                                                                             │
     ▼               ▼                                                                             │
┌──────────┐   ┌──────────┐                                                                 ┌────────────┐
│cancelled │   │cancelled │                                                                 │  cancelled │
└──────────┘   └──────────┘                                                                 └────────────┘
     │
     ▼
┌──────────┐
│ no_show  │  (auto-expire después de departure+15min o passenger_report_no_show)
└──────────┘
```

### Transiciones y quién las ejecuta

| Transición | Actor | RPC |
|-----------|-------|-----|
| reserved → accepted | Conductor | `driver_accept_booking` |
| accepted → driver_arriving | Conductor | `driver_mark_arriving` |
| driver_arriving → driver_arrived | Conductor | `driver_mark_arrived` |
| driver_arrived → passenger_boarded | Pasajero | `confirm_boarding` |
| passenger_boarded → in_progress | Conductor | `driver_start_trip` |
| in_progress → completed | Conductor | `driver_complete_trip` |
| reserved → cancelled | Pasajero | `cancel_booking` |
| reserved → cancelled | Conductor | `driver_reject_booking` |
| cualquier estado → cancelled | Sistema | `expire_stale_bookings_and_release` |
| cualquier estado → no_show | Pasajero | `passenger_report_no_show` |
| cualquier estado → no_show | Sistema | `expire_stale_bookings_and_release` |

Cada transición se registra en `booking_events` con: `from_status`, `to_status`, `actor_user_id`, `actor_role`, `event_type`, `metadata`.

---

## 13. SISTEMA DE STRIKES Y SUSPENSIONES

### Qué genera un strike

1. **Conductor cancela un ride <2 horas antes del departure**
2. **Pasajero reporta no-show** (conductor no llegó al punto de encuentro)

### Reglas

- Cada strike tiene un `expires_at` = 2 meses desde creación
- `strikes_count` = count de strikes **no expirados** del conductor
- **2 strikes activos** → suspensión automática:
  - `suspended_until` = ahora + 2 meses (bloquea modo conductor)
  - `vehicle_suspended_until` = ahora + 2 meses (bloquea ese vehículo)
- Trigger `trg_refresh_user_strike_state` recalcula automáticamente en cada INSERT/UPDATE/DELETE de strikes
- RPC `is_driver_banned_now()` verifica si el conductor está suspendido

### Efecto de la suspensión

- No puede publicar nuevos turnos (RLS policy `rides_driver_insert`)
- No puede cambiar a modo conductor desde el home
- El vehículo queda bloqueado

---

## 14. SISTEMA DE RESEÑAS Y FAVORITOS

### Reseñas

- Solo se puede reseñar en bookings con `dispatch_status = completed`
- Ventana de 30 días desde la completación
- Una reseña por persona por booking (unique constraint)
- No se puede reseñar a sí mismo
- Estrellas: 1-5, comentario opcional (máx 500 chars)
- Las reseñas son públicas por default (`is_public = true`)
- Al enviar una reseña, se recalcula `rating_avg` y `rating_count` del reviewee
- Tanto pasajero como conductor pueden reseñarse mutuamente

### Favoritos

- Relación many-to-many entre usuarios (`user_favorites` table)
- Toggle: si existe → elimina, si no existe → inserta
- No se puede favoritar a sí mismo (check constraint)
- Se puede filtrar por rol (driver/passenger)
- Se crean desde booking_screen, my_rides_screen, active_trip_screen, driver_rides_screen

---

## 15. SISTEMA DE NOTIFICACIONES

La app tiene **3 capas** de notificaciones:

### 1. Notificaciones locales (flutter_local_notifications)

- Solo activas en iOS
- Se disparan desde `BookingNotificationService` cuando detecta un cambio de estado
- Muestran alertas nativas del sistema operativo

### 2. Notificaciones push (APNs)

- Solo iOS nativo
- El device token se registra en `device_tokens` al autenticarse
- Se envían automáticamente vía trigger DB:
  - Trigger `booking_event_push_trigger` en `booking_events` table
  - Llama función `push_notify_dispatch_change` que usa `pg_net` para hacer HTTP POST a la edge function `send-push-notification`
- La edge function envía a APNs con JWT ES256

### 3. Notificaciones in-app

- Gestionadas por `inAppNotificationProvider` (Riverpod)
- Se alimentan desde `BookingNotificationService` (callback)
- Se muestran en `/notifications` screen
- Soportan: leído/no leído, marcar todo como leído, máx 100 notificaciones

---

## 16. ENRUTAMIENTO Y PROTECCIÓN DE RUTAS

### GoRouter

- `initialLocation: '/home'`
- **Guard de autenticación:** función `redirect` que se ejecuta antes de cada navegación
- **Refresh stream:** escucha `onAuthStateChange` de Supabase → notifica a GoRouter para re-evaluar

### Rutas públicas (no requieren auth)

- `/login`, `/register`, `/terms`, `/privacy`, `/support`

### Redirecciones automáticas

- Sin sesión + ruta protegida → `/login`
- Con sesión + ruta de auth → `/home`

---

## 17. MANEJO DE ERRORES

### Arquitectura de errores

1. **Capa DB:** Errores PostgreSQL con códigos custom (`P0001`, `P0002`, etc.)
2. **Capa servicios:** `BookingService` mapea errores Postgrest a strings
3. **Capa global:** `AppErrorMapper.toMessage()` convierte cualquier error técnico a mensaje en español

### Códigos de error custom de la DB

| Código | Significado |
|--------|------------|
| `P0001` | Unauthorized / sesión expirada |
| `P0002` | Ride unavailable |
| `P0003` | Already booked |
| `P0004` | Insufficient balance |
| `P0005` | Already processed |
| `P0006` | Forbidden |
| `P0008` | Wait time not elapsed |
| `P0010` | Ride departed |
| `P0011` | Invalid dispatch transition |
| `P0012` | Held balance mismatch |
| `P0013` | Report/cancel window expired |
| `P0014` | Review errors |
| `P0015` | Driver banned / vehicle suspended |
| `P0016` | Overlapping booking |
| `P0017` | Auto-expired booking |

### Fallback global

Si ningún patrón coincide → "No pudimos completar la operación. Intenta nuevamente."

---

## 18. DESPLOY

### Backend — Supabase Cloud

```bash
supabase login
supabase link --project-ref zawaevytpkvejhekyokw
supabase db push
supabase functions deploy create-topup-intent --no-verify-jwt
supabase functions deploy fintoc-webhook --no-verify-jwt
supabase functions deploy send-push-notification --no-verify-jwt
supabase functions deploy delete-account --no-verify-jwt
```

---

## 19. VARIABLES DE ENTORNO

### Flutter (dart-define)

| Variable | Uso |
|----------|-----|
| `SUPABASE_URL` | URL del proyecto Supabase |
| `SUPABASE_ANON_KEY` | Key pública anon para el cliente Flutter |

### Supabase Edge Functions (Dashboard → Settings → Edge Functions → Secrets)

| Variable | Uso |
|----------|-----|
| `FINTOC_SECRET_KEY` | Secret key de Fintoc (`sk_test_xxx` para sandbox, `sk_live_xxx` para producción) — **pendiente de obtener** |
| `FINTOC_WEBHOOK_SECRET` | Secret para validar firma de webhooks Fintoc — **pendiente de obtener** |
| `APP_BASE_URL` | URL pública de la app |
| `PAYMENT_PROVIDER` | `fintoc` o `disabled` |
| `SUPABASE_URL` | URL del proyecto |
| `SUPABASE_SERVICE_ROLE_KEY` | Key admin (nunca exponer en frontend) |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_KEY_BASE64` | Push notifications APNs |
| `INTERNAL_PUSH_SECRET` | Secret para llamadas internas de push |

> Ver [`FINTOC_SETUP.md`](FINTOC_SETUP.md) para el checklist completo de keys Fintoc y pasos de sandbox.

---

## 20. FLUJOS END-TO-END

### 19.1. Registro

```
1. Usuario abre app → GoRouter redirige a /login (sin sesión)
2. Toca "Registrarse" → /register
3. Completa: nombre, email, password, universidad
4. Opcionalmente: toggle "ser conductor" → llena datos de vehículo
5. Acepta términos + declara licencia
6. AuthService.signUp() → Supabase Auth crea usuario
7. Trigger DB `on_auth_user_created` → crea users_profile + wallets
8. GoRouter detecta auth change → redirige a /home
```

### 19.2. Publicar turno (conductor)

```
1. Home → toggle a modo conductor
2. Validación: términos ✓, licencia ✓, vehículo ✓, no suspendido ✓
3. Toca "Publicar turno" → /publish
4. Completa formulario: dirección, comuna, universidad, campus, punto de encuentro, radial, fecha/hora, asientos
5. PublishRideScreen valida: términos, licencia, hora futura
6. RideService.createRide() → INSERT en rides
7. Triggers DB: enforce_ride_pricing + compute_ride_pricing ajustan precios
8. Pop → vuelve al home
```

### 19.3. Reservar turno (pasajero)

```
1. Home → "Buscar turno" → /search
2. Aplica filtros: comuna, dirección, campus, fecha
3. searchRidesProvider.search() → RideService.searchRides()
4. Selecciona turno → /booking/:rideId
5. BookingScreen carga: detalle turno, saldo, perfil conductor, reseñas
6. Verifica saldo suficiente
7. Diálogo de confirmación
8. BookingService.createBooking(rideId) → RPC create_booking
9. DB: valida disponibilidad, retiene saldo (available→held), decrementa asientos
10. Navega a /my-rides
```

### 19.4. Flujo de despacho completo

```
1. Conductor ve reserva pendiente → acepta (driver_accept_booking)
   dispatch: reserved → accepted
   Pasajero recibe notificación: "Te han confirmado el Ride"

2. Conductor se dirige al punto → marca "en camino" (driver_mark_arriving)
   dispatch: accepted → driver_arriving
   Pasajero recibe notificación: "El rider va en camino"

3. Conductor llega al punto → marca "llegó" (driver_mark_arrived)
   dispatch: driver_arriving → driver_arrived
   Pasajero recibe notificación: "El rider ha llegado"

4. Pasajero sube al auto → confirma abordaje (confirm_boarding)
   dispatch: driver_arrived → passenger_boarded

5. Conductor inicia viaje → "iniciar viaje" (driver_start_trip)
   dispatch: passenger_boarded → in_progress

6. Conductor llega a destino → "finalizar viaje" (driver_complete_trip)
   dispatch: in_progress → completed
   DB: libera held del pasajero, acredita neto al conductor, registra platform_fee
   Pasajero recibe notificación: "Viaje finalizado"
```

### 19.5. Recarga de billetera

```
1. Home → Wallet card → /wallet
2. Toca "Recargar" → bottom sheet con montos rápidos
3. Selecciona monto (ej: $10.000) → confirma con fee del 1% visible
4. createTopupIntent(10000) → Edge Function crea Checkout Session Fintoc
5. fintoc_payments: INSERT status=pending (checkout_session_id, amounts)
6. App abre redirect_url en el navegador → usuario paga en Fintoc (modo test)
7. Fintoc redirige a turnoapp://wallet?topup=success → app vuelve a /wallet
8. Fintoc envía checkout_session.finished + payment_intent.succeeded
9. fintoc-webhook verifica firma → credit_wallet_topup → pending→approved
10. DB: wallets.balance_available += 10000, transactions (type=topup)
11. walletProvider (realtime + deep link) actualiza la UI
```

### 19.6. Cancelación con reembolso

```
1. Pasajero en /my-rides → toca "Cancelar" en reserva activa
2. Validación: viaje no iniciado + dentro de ventana de cancelación
3. BookingService.cancelBooking(bookingId) → RPC cancel_booking
4. DB: wallets.balance_held -= amount, balance_available += amount
5. DB: INSERT transactions (type=refund, amount=+amount)
6. DB: bookings.status = 'cancelled', dispatch_status = 'cancelled'
7. DB: rides.seats_available += 1
8. Actualiza UI
```

---

## 21. ESTADO ACTUAL, PENDIENTES Y RIESGOS

### Implementado y funcional

- Auth email/password con Supabase
- Registro con aceptación de términos y licencia
- Cambio de modo pasajero/conductor con gate de seguridad
- Publicación de turnos con punto de encuentro, radial, pricing automático
- Búsqueda y reserva de turnos con filtros
- Sistema de despacho completo (7 estados)
- Confirmación de abordaje (libera pago)
- Cancelación con reembolso
- Reporte no-show
- Cancelación de turno por conductor con reembolso
- Sistema de strikes y suspensión
- Wallet y recarga vía Fintoc (Checkout Session + webhook, listo para keys de sandbox — ver `FINTOC_SETUP.md`)
- Retiro sandbox
- Reseñas post-viaje
- Favoritos de usuarios
- Notificaciones in-app, locales y push
- Supabase Realtime (5 canales: rides, bookings, wallet, profile)
- Perfil editable con foto
- Eliminación de cuenta
- Ledger inmutable
- RLS en todas las tablas sensibles
- CI/CD iOS con Codemagic (configurado, pendiente conectar cuenta)

### Pendientes

**P0 (corto plazo):**
- ~~Obtener API keys de Fintoc (test) y seguir `FINTOC_SETUP.md`~~ ✅ Sandbox verificado end-to-end (2026-08-25)
- Publicar `turnoapp.cl` + universal links para el retorno a la app tras pagar
- Conectar Codemagic al repo + App Store Connect
- Ajustar UX de políticas y mensajes de strikes

**P1 (siguiente iteración):**
- Implementar multas monetarias explícitas
- Botón de pánico real con url_launcher + registro de evento

**P2 (largo alcance):**
- Live chat (tabla mensajes + realtime)
- Tema oscuro completo
- Verificación documental real de licencia (KYC)

### Riesgos técnicos

- **No hay suite de tests automatizados** — validación predominantemente manual
- **Fallback local de referencias** puede enmascarar problemas de RLS en QA
- **Redirección post-pago a `turnoapp.cl`** — dominio sin publicar; el crédito funciona igual vía webhook (billetera se actualiza por realtime)
- **CORS `*`** en todas las edge functions — revisar para producción

---

## 22. GUÍA PARA COLABORAR EN EL PROYECTO

### Dónde tocar qué

| Quieres cambiar... | Dónde ir |
|-------------------|----------|
| Agregar una pantalla | `lib/features/nueva_feature/` + ruta en `lib/app/router.dart` |
| Cambiar colores/tema | `lib/app/theme.dart` |
| Agregar un modelo de datos | `lib/models/` |
| Llamar al backend de forma nueva | `lib/services/` |
| Agregar estado global | `lib/providers/` (StateNotifier + Provider) |
| Cambiar precios/reglas de negocio | `lib/core/constants.dart` **Y** migración DB correspondiente |
| Cambiar esquema DB | Nueva migración en `supabase/migrations/` |
| Agregar edge function | Nueva carpeta en `supabase/functions/` |
| Cambiar mensajes de error | `lib/core/error_mapper.dart` |

### Convenciones del proyecto

- **Modelos:** inmutables, factory `fromJson`, `toJson` para upsert, `copyWith`
- **Servicios:** instancian `SupabaseConfig.client` internamente, exponen métodos de alto nivel
- **Providers:** StateNotifier + StateNotifierProvider, estado inmutable con copyWith
- **Pantallas:** ConsumerStatefulWidget (Riverpod), usan LoadingOverlay + AppSnackbar
- **Nombres:** snake_case para archivos, camelCase para variables, PascalCase para clases
- **Idioma:** código en inglés (nombres de variables, funciones), UI en español

### Antes de hacer commit

```bash
cd turnoapp
flutter analyze    # Debe pasar sin errores
flutter test       # Si hay tests
```

### Push de migraciones DB

```bash
cd supabase
supabase db push   # Aplica solo migraciones pendientes
```

---

## 23. GLOSARIO

| Término | Definición |
|---------|-----------|
| **PWA** | Progressive Web App — versión web de la app accesible desde navegador (conservada como fallback) |
| **RLS** | Row Level Security — reglas de seguridad a nivel de fila en PostgreSQL |
| **RPC** | Remote Procedure Call — función ejecutada en la DB (funciones PL/pgSQL) |
| **Idempotencia** | Procesar múltiples veces un mismo evento sin duplicar su efecto |
| **Ledger** | Registro contable inmutable de todos los movimientos financieros |
| **SECURITY DEFINER** | Función PL/pgSQL que se ejecuta con los privilegios de su creador, ignorando RLS |
| **Turno / Ride** | Viaje publicado por un conductor con ruta, horario y cupos |
| **Reserva / Booking** | Reserva de un pasajero en un turno específico |
| **Dispatch** | Máquina de estados que controla el ciclo de vida de una reserva |
| **Strike** | Falta registrada a un conductor (cancelación tardía, no-show) |
| **Sandbox** | Modo de prueba de la pasarela (Fintoc test mode): pagos simulados con credenciales de test, sin mover dinero real |
| **Edge Function** | Función serverless ejecutada en Supabase (Deno runtime) |
| **PostgREST** | API REST automática que expone PostgreSQL |
| **pg_net** | Extensión de PostgreSQL para hacer peticiones HTTP desde la DB |
| **APNs** | Apple Push Notification service |
| **ES256** | Algoritmo de firma JWT con curva elíptica P-256 (usado por APNs) |
| **Codemagic** | Plataforma CI/CD especializada en Flutter para build y publicación en App Store |
| **Fintoc** | Proveedor de pagos chileno (Checkout Sessions vía API REST) |

---

> **Nota final:** Este documento refleja el estado del proyecto a abril de 2026. Para el estado más actualizado, consultar el código fuente directamente y las migraciones más recientes en `supabase/migrations/`.

---
