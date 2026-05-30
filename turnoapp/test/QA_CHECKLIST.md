# QA Checklist — UniRide TestFlight Beta

## Datos de prueba

| Cuenta | Rol | Balance |
|--------|-----|---------|
| `pasajero@demo.com` / `demo1234` | Pasajero | $50,000 |
| `conductor@demo.com` / `demo1234` | Conductor | $50,000 |

---

## 1. Registro y autenticación

- [ ] **1.1** Registro con email válido, contraseña >= 6 caracteres, nombre, universidad, términos aceptados → redirige a login/home
- [ ] **1.2** Registro sin aceptar términos → error: "Debes aceptar terminos y condiciones"
- [ ] **1.3** Registro como conductor con datos de vehículo completos → perfil guarda vehículo
- [ ] **1.4** Registro con email ya existente → error: "Este correo ya tiene una cuenta"
- [ ] **1.5** Login con credenciales correctas → redirige a `/home`
- [ ] **1.6** Login con credenciales incorrectas → error: "Correo o contrasena incorrectos"
- [ ] **1.7** Login con contraseña < 6 caracteres → validación: "Minimo 6 caracteres"
- [ ] **1.8** Login con email sin @ → validación: "Correo invalido"
- [ ] **1.9** Toggle visibilidad de contraseña → cambia ícono y muestra/oculta contraseña
- [ ] **1.10** Cerrar sesión → redirige a `/login`, no queda sesión abierta

---

## 2. Pantalla Home

- [ ] **2.1** Muestra nombre del usuario, foto (o placeholder), y balance
- [ ] **2.2** Toggle de rol: pasajero ↔ conductor cambia las acciones mostradas
- [ ] **2.3** Cambio a conductor sin vehículo → modal solicita datos de vehículo
- [ ] **2.4** Pull-to-refresh recarga perfil y balance
- [ ] **2.5** Badge de notificaciones muestra conteo de no leídas
- [ ] **2.6** Links de navegación: Favoritos, Privacidad, Términos, Soporte
- [ ] **2.7** Tarjeta de seguridad muestra strikes y suspensiones si existen

---

## 3. Publicar turno (conductor)

- [ ] **3.1** Seleccionar dirección (hacia/desde campus)
- [ ] **3.2** Seleccionar comuna, universidad → carga campuses dinámicamente
- [ ] **3.3** Seleccionar fecha y hora futura → validación: no permite fechas pasadas
- [ ] **3.4** Ajustar número de asientos (1-6)
- [ ] **3.5** Vista previa de precio: precio por asiento + comisión + neto conductor
- [ ] **3.6** Publicar turno con todos los campos → éxito, navega a home
- [ ] **3.7** Publicar sin aceptar términos → error: "Debes aceptar terminos y condiciones"
- [ ] **3.8** Toggle radial (solo Chicureo) → muestra campo de ruta radial

---

## 4. Buscar turno (pasajero)

- [ ] **4.1** Filtros iniciales: comuna, dirección, campus, fecha
- [ ] **4.2** Botón "Buscar" → muestra resultados como tarjetas
- [ ] **4.3** Estado vacío antes de buscar: "Filtra o presiona buscar para ver turnos disponibles"
- [ ] **4.4** Sin resultados: "No hay turnos disponibles con estos filtros"
- [ ] **4.5** Cada tarjeta muestra: ruta, hora, precio, asientos disponibles
- [ ] **4.6** Tap en tarjeta → navega a detalle del turno

---

## 5. Detalle de turno y reserva

- [ ] **5.1** Muestra info del turno: ruta, fecha/hora, asientos, precio
- [ ] **5.2** Muestra perfil del conductor: nombre, rating, vehículo, contacto emergencia
- [ ] **5.3** Muestra reseñas públicas del conductor (top 5)
- [ ] **5.4** Botón de reportar conductor
- [ ] **5.5** Botón de bloquear conductor
- [ ] **5.6** Botón de favorito (toggle)
- [ ] **5.7** Desglose de pago: precio asiento + comisión plataforma
- [ ] **5.8** Reservar con saldo suficiente → éxito, navega a "Mis turnos"
- [ ] **5.9** Reservar sin saldo suficiente → error: "Saldo insuficiente"
- [ ] **5.10** Turno sin cupos → muestra "sin cupos"

---

## 6. Ciclo de vida del viaje — Pasajero

- [ ] **6.1** Tab "Activas" muestra reservas en curso
- [ ] **6.2** Tab "Historial" muestra reservas pasadas
- [ ] **6.3** Booking en estado "accepted": muestra botón "Me subí al auto"
- [ ] **6.4** Booking en estado "driver_arriving": muestra progreso
- [ ] **6.5** Confirmar abordaje → booking cambia a "passenger_boarded"
- [ ] **6.6** Pantalla de viaje activo muestra progreso de 7 pasos
- [ ] **6.7** Al completar viaje → pantalla de llegada ("Llegaste a destino!")
- [ ] **6.8** Cancelar reserva desde "Mis turnos" → booking cambia a cancelado
- [ ] **6.9** Reportar no-show del conductor → booking cambia a no_show
- [ ] **6.10** Calificar conductor después de viaje completado (1-5 estrellas)

---

## 7. Ciclo de vida del viaje — Conductor

- [ ] **7.1** Tab "Activos" muestra turnos publicados activos
- [ ] **7.2** Tab "Pasajeros" muestra bookings con badge de pendientes
- [ ] **7.3** Aceptar pasajero → dispatch cambia a "accepted"
- [ ] **7.4** Rechazar pasajero → booking rechazado
- [ ] **7.5** Marcar "llegando" → dispatch cambia a "driver_arriving"
- [ ] **7.6** Marcar "llegué" → dispatch cambia a "driver_arrived"
- [ ] **7.7** Iniciar viaje (espera abordaje del pasajero) → dispatch a "in_progress"
- [ ] **7.8** Completar viaje → dispatch a "completed"
- [ ] **7.9** "Iniciar viaje para todos" (bulk) → todos los pasajeros abordo inician
- [ ] **7.10** "Finalizar viaje completo" → cierra el turno completo
- [ ] **7.11** Cancelar turno → ride cancelado, bookings liberados

---

## 8. Billetera

- [ ] **8.1** Muestra balance disponible
- [ ] **8.2** Muestra historial de transacciones (topup, booking_hold, refund, etc.)
- [ ] **8.3** Estado vacío: "Sin movimientos aun"
- [ ] **8.4** Recargar con chips rápidos ($5,000, $10,000, $20,000, $50,000)
- [ ] **8.5** Retirar con monto válido (mín $20,000, máx balance)
- [ ] **8.6** Retirar con monto inválido → muestra error de validación
- [ ] **8.7** Balance se actualiza después de recarga/retiro

---

## 9. Perfil

- [ ] **9.1** Editar nombre, teléfono emergencia, notas de seguridad
- [ ] **9.2** Editar datos del vehículo (marca, modelo, versión, puertas, patente, color)
- [ ] **9.3** Subir foto de perfil (cámara o galería)
- [ ] **9.4** Toggle de licencia vigente (declaración jurada)
- [ ] **9.5** Eliminar cuenta → diálogo de confirmación + razón
- [ ] **9.6** Eliminar cuenta exitosa → redirige a login

---

## 10. Favoritos

- [ ] **10.1** Lista de favoritos cargada
- [ ] **10.2** Filtro por rol (Todos / Conductores / Pasajeros)
- [ ] **10.3** Long-press → acciones: quitar favorito, reportar, bloquear
- [ ] **10.4** Quitar favorito → confirmación y eliminación
- [ ] **10.5** Estado vacío: "Aun no agregas usuarios a favoritos"

---

## 11. Notificaciones

- [ ] **11.1** Lista de notificaciones in-app cargadas
- [ ] **11.2** Marca todas como leídas al entrar
- [ ] **11.3** Diferencia visual entre leídas y no leídas
- [ ] **11.4** Estado vacío: "Sin notificaciones aun"

---

## 12. Reportes y bloqueos

- [ ] **12.1** Reportar usuario: seleccionar categoría y agregar detalles
- [ ] **12.2** Bloquear usuario → confirmación
- [ ] **12.3** No se pueden ver turnos de usuarios bloqueados
- [ ] **12.4** No se puede interactuar con usuarios bloqueados

---

## 13. Pantallas legales

- [ ] **13.1** Términos y condiciones: contenido cargado correctamente
- [ ] **13.2** Política de privacidad: contenido cargado correctamente
- [ ] **13.3** Soporte: email (mailto:) y llamada de emergencia (tel:133)

---

## 14. Pruebas en dispositivo iOS real

- [ ] **14.1** Push notifications: recibir notificación al cambiar estado de booking
- [ ] **14.2** App en background: las notificaciones llegan correctamente
- [ ] **14.3** App cerrada: abrir desde notificación navega al booking correcto
- [ ] **14.4** Rotación de pantalla: layouts no se rompen
- [ ] **14.5** Modo oscuro: colores y contraste correctos
- [ ] **14.6** Conexión lenta/intermitente: mensajes de error apropiados
- [ ] **14.7** Sin conexión: mensaje "No hay conexion a internet"
- [ ] **14.8** Prueba con dos dispositivos: flujo pasajero + conductor en tiempo real

---

## 15. Edge cases

- [ ] **15.1** Doble tap en botones de acción no envía dos requests
- [ ] **15.2** App en background > 5 min → realtime se reconecta correctamente
- [ ] **15.3** Sesión expirada → mensaje: "Sesion expirada. Cierra sesion y vuelve a iniciar"
- [ ] **15.4** Texto muy largo en campos de perfil no rompe el layout
- [ ] **15.5** Scroll funciona en todas las pantallas con listas largas
- [ ] **15.6** Teclado no oculta campos al escribir en formularios
- [ ] **15.7** Cerrar y reabrir la app → la sesión persiste

---

**Total: 73 puntos de verificación**
