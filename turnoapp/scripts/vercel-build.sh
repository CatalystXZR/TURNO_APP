#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/flutter-sdk/bin:$PATH"

SUPABASE_URL_CLEAN="$(printf %s "${SUPABASE_URL:-}" | tr -d '\r\n')"
SUPABASE_ANON_KEY_CLEAN="$(printf %s "${SUPABASE_ANON_KEY:-}" | tr -d '\r\n')"

flutter pub get
flutter build web --release --dart-define="SUPABASE_URL=$SUPABASE_URL_CLEAN" --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY_CLEAN"
