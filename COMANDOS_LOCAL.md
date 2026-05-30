# Turno — Comandos para correr local

## 1. Alias de Supabase (solo la primera vez)
```bash
alias supabase="~/.npm/_npx/aa8e5c70f9d8d161/node_modules/supabase/bin/supabase"
```

## 2. Correr la app en Chromium
```bash
cd ~/Escritorio/PERSONAL/uniride/turno
flutter pub get
flutter run -d edge \
  --dart-define=SUPABASE_URL=https://zawaevytpkvejhekyokw.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inphd2Fldnl0cGt2ZWpoZWt5b2t3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNzAwMjEsImV4cCI6MjA4ODk0NjAyMX0.W08CHoJ_jKSHzBvQnw-HUfjTBSdNVGBs6N89h_QPaOM
```

## 3. Cuentas demo
| Tipo | Email | Password |
|------|-------|----------|
| Pasajero | pasajero@demo.com | demo1234 |
| Conductor | conductor@demo.com | demo1234 |

## 4. Probar recarga con Fintoc (modo test)
- Wallet → Recargar → elegir monto
- En la página de Fintoc, usar: RUT `41614850-3`, clave `jonsnow`, cuenta `422159212`
- Esperar 5 segundos → pago exitoso → webhook acredita billetera

## 5. Deploy de edge functions (si haces cambios)
```bash
cd ~/Escritorio/PERSONAL/uniride/supabase
supabase functions deploy create-topup-intent --no-verify-jwt
supabase functions deploy fintoc-webhook --no-verify-jwt
supabase functions deploy send-push-notification --no-verify-jwt
supabase functions deploy delete-account --no-verify-jwt
```

## 6. Aplicar migraciones (si haces cambios en DB)
```bash
cd ~/Escritorio/PERSONAL/uniride/supabase
supabase db push
```
