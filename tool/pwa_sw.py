#!/usr/bin/env python3
"""يكتب عامل الخدمة sw.js لنسخة الويب (PWA) من تطبيق مبني: يحفظ ملفاته في الجهاز فيُفتح فوراً ويعمل دون إنترنت.

عامل Flutter نفسه متروك (يلغي تسجيله)، فهذا بديله:
- عند التثبيت يُحفظ «هيكل» التطبيق كله مسبقاً (الصفحة، والمحمّل، والخطوط والصور، وSQLite المترجم، وعامل
  القاعدة)، ويُحفظ ما عداه (كود التطبيق المترجم ومحرّك الرسم) أول ما يُطلب، فلا ينزّل الهاتف إلا ما يستعمله
  متصفحه (WebAssembly أو JavaScript).
- كل طلب للموقع نفسه يُجاب من الذاكرة أولاً (أسرع فتح ممكن ودون إنترنت)، والصفحة نفسها عند أي تنقل.
- مكتبات من شبكات التوزيع (قارئ الرموز بالكاميرا مثلاً) تُحفظ عند أول استعمال.
- طلبات خادم المدرسة (Supabase) لا تُعترض أبداً: البيانات تمر بالمزامنة وقاعدة المتصفح.
- اسم الذاكرة يتبع بصمة الملفات: إصدار جديد يثبّت عاملاً جديداً يحذف القديم، فيُفتح التطبيق الجديد في الفتح التالي.

الاستعمال:
  python3 tool/pwa_sw.py <مجلد build/web> <اسم التطبيق>
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

# تُحفظ عند أول طلب لا مسبقاً: يستعمل المتصفح أحدها فقط (WebAssembly أو JavaScript، ومحرّك رسم واحد).
LAZY_PREFIXES = ("canvaskit/",)
# ونص التراخيص (NOTICES، نحو 1.5 م.ب) لا يُفتح إلا من صفحة التراخيص.
LAZY_FILES = {"main.dart.js", "main.dart.mjs", "main.dart.wasm", "assets/NOTICES"}
# لا تُحفظ: العامل نفسه، وعامل Flutter المتروك، وملفات البناء الداخلية والخرائط.
SKIP_FILES = {"sw.js", "flutter_service_worker.js", ".last_build_id"}
SKIP_SUFFIXES = (".map", ".deps", ".symbols")
# مكتبات خارجية تُحفظ عند أول استعمال.
CDN_HOSTS = ("cdn.jsdelivr.net", "unpkg.com", "fonts.gstatic.com", "fonts.googleapis.com")


def site_files(root: Path) -> list[str]:
    """كل ملفات البناء بمساراتها النسبية (بشرطة مائلة) مرتبة، دون المستثناة."""
    files = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel in SKIP_FILES or rel.endswith(SKIP_SUFFIXES):
            continue
        files.append(rel)
    return files


def precached(files: list[str]) -> list[str]:
    """ما يُحفظ عند التثبيت: كل شيء عدا كود التطبيق المترجم ومحرّكات الرسم."""
    return [f for f in files if f not in LAZY_FILES and not f.startswith(LAZY_PREFIXES)]


def version(root: Path, files: list[str]) -> str:
    """بصمة محتوى كل الملفات: تتغير بأي تغيير فيُثبَّت عامل جديد."""
    digest = hashlib.sha256()
    for rel in files:
        digest.update(rel.encode("utf-8"))
        digest.update(hashlib.sha256((root / rel).read_bytes()).digest())
    return digest.hexdigest()[:16]


def render(app: str, cache_version: str, shell: list[str]) -> str:
    """نص sw.js."""
    prefix = f"school-{app}-"
    return f"""// مولَّد بـ tool/pwa_sw.py — لا يُعدَّل يدوياً.
'use strict';
const PREFIX = {json.dumps(prefix)};
const CACHE = PREFIX + {json.dumps(cache_version)};
const RUNTIME = PREFIX + 'cdn';
const SHELL = {json.dumps(["./", *shell], ensure_ascii=False)};
const CDN_HOSTS = {json.dumps(list(CDN_HOSTS))};

self.addEventListener('install', (event) => {{
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(SHELL.map((path) => new Request(path, {{ cache: 'no-cache' }}))))
      .then(() => self.skipWaiting()),
  );
}});

self.addEventListener('activate', (event) => {{
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith(PREFIX) && key !== CACHE && key !== RUNTIME)
          .map((key) => caches.delete(key)),
      ))
      .then(() => self.clients.claim()),
  );
}});

async function fromCacheFirst(cacheName, request, key) {{
  const cache = await caches.open(cacheName);
  const hit = await cache.match(key || request, {{ ignoreSearch: true }});
  if (hit) return hit;
  const response = await fetch(request);
  if (response && (response.ok || response.type === 'opaque')) {{
    cache.put(key || request, response.clone());
  }}
  return response;
}}

self.addEventListener('fetch', (event) => {{
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin === self.location.origin) {{
    // أي تنقل داخل التطبيق يفتح الصفحة المحفوظة (يعمل دون إنترنت).
    if (request.mode === 'navigate') {{
      event.respondWith(fromCacheFirst(CACHE, request, './').catch(() => caches.match('./')));
      return;
    }}
    event.respondWith(fromCacheFirst(CACHE, request));
    return;
  }}
  if (CDN_HOSTS.includes(url.hostname)) {{
    event.respondWith(fromCacheFirst(RUNTIME, request));
  }}
  // غير ذلك (خادم المدرسة ودليل المدارس): الشبكة مباشرة دون اعتراض.
}});
"""


def write(root: Path, app: str) -> Path:
    files = site_files(root)
    if "index.html" not in files:
        raise SystemExit(f"لا index.html في {root}: ليس مجلد بناء ويب")
    out = root / "sw.js"
    out.write_text(render(app, version(root, files), precached(files)), encoding="utf-8")
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    out = write(Path(argv[1]), argv[2])
    print(f"pwa-sw: {out} ({len(precached(site_files(Path(argv[1]))))} files precached)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
