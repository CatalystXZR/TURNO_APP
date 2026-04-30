#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.29.3"
FLUTTER_DIR="$HOME/flutter-sdk"

if [ ! -d "$FLUTTER_DIR" ]; then
  mkdir -p "$HOME"
  curl -sL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" | tar xJ -C "$HOME"
  mv "$HOME/flutter" "$FLUTTER_DIR"
fi

chown -R "$(id -u):$(id -g)" "$FLUTTER_DIR"

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter config --enable-web --no-analytics
