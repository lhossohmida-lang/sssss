#!/usr/bin/env bash
# يثبّت Flutter المستقر في /opt/flutter إن لم يكن موجوداً، ثم يجلب حزم المشروع.
# الاستعمال: source tool/setup_env.sh
set -euo pipefail
FLUTTER_VERSION="3.47.9"
if [ ! -x /opt/flutter/bin/flutter ]; then
  curl -sS -o /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  tar xf /tmp/flutter.tar.xz -C /opt
  rm -f /tmp/flutter.tar.xz
  git config --global --add safe.directory /opt/flutter
fi
export PATH="/opt/flutter/bin:$PATH"
flutter config --no-analytics >/dev/null 2>&1 || true
flutter pub get
