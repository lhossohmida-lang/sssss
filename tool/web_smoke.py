#!/usr/bin/env python3
"""اختبار دخان لنسخة الويب (PWA) في Chrome دون واجهة: يفتح كل تطبيق من الموقع المبني ويتحقق أنه يصل شاشته الأولى،
ثم يقطع الإنترنت ويعيد فتحه فيصلها من جديد (عامل الخدمة وقاعدة المتصفح)، ويقيس زمن الفتح.

يحتاج playwright (pip install playwright ثم playwright install --with-deps chromium) وموقعاً مبنياً فيه
<app>/index.html لكل تطبيق. يكتب لقطة شاشة لكل تطبيق وملخصاً JSON، ويخرج بـ1 إن فشل أي تطبيق.

الاستعمال:
  python3 tool/web_smoke.py <مجلد الموقع> <مجلد المخرجات>
"""

from __future__ import annotations

import functools
import http.server
import json
import mimetypes
import socketserver
import sys
import threading
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

# ما يجب أن يظهر في الشاشة الأولى (البناء العام يضمّن دليل المدارس).
FIRST_SCREENS = {
    "admin": "أدخل رقم هاتفك وكلمة السر",
    "teacher": "اختر مدرستك",
    "student": "اختر مدرستك",
}
TIMEOUT_MS = 90_000
LOCAL_PREVIEW = "تجربة محلية بلا خادم"
START_FAILED = "تعذّر تشغيل التطبيق"

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("text/javascript", ".mjs")


@dataclass
class WebOutcome:
    app: str
    online_ms: int = -1
    offline_ms: int = -1
    service_worker: bool = False
    texts: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    # تنبيهات لا تمنع النشر (التشغيل المحلي للإدارة: نقر Chrome على أزرار Flutter غير مضمون).
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.problems


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):  # noqa: D401 — بلا سجل لكل طلب
        pass


def serve(root: Path) -> tuple[socketserver.TCPServer, str]:
    handler = functools.partial(_QuietHandler, directory=str(root))
    server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}"


def visible_texts(page) -> list[str]:
    """نصوص الشاشة من شجرة الوصول في Flutter (تُفعَّل بزر «Enable accessibility» المخفي)."""
    page.evaluate(
        "() => { const b = document.querySelector('flt-semantics-placeholder');"
        " if (b) b.click(); }"
    )
    return page.evaluate(
        "() => Array.from(document.querySelectorAll('flt-semantics, [aria-label]'))"
        ".map(e => (e.getAttribute('aria-label') || e.textContent || '').trim())"
        ".filter(t => t.length > 0)"
    )


def wait_for_text(page, expected: str) -> list[str]:
    deadline = time.monotonic() + TIMEOUT_MS / 1000
    texts: list[str] = []
    while time.monotonic() < deadline:
        texts = visible_texts(page)
        if any(expected in t for t in texts):
            return texts
        page.wait_for_timeout(500)
    return texts


def smoke_app(browser, base: str, app: str, out_dir: Path) -> WebOutcome:
    outcome = WebOutcome(app)
    expected = FIRST_SCREENS[app]
    context = browser.new_context(viewport={"width": 390, "height": 844}, locale="ar")
    page = context.new_page()
    errors: list[str] = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    url = f"{base}/{app}/"
    try:
        start = time.monotonic()
        page.goto(url, wait_until="load", timeout=TIMEOUT_MS)
        texts = wait_for_text(page, expected)
        outcome.online_ms = int((time.monotonic() - start) * 1000)
        outcome.texts = texts[:12]
        if not any(expected in t for t in texts):
            outcome.problems.append(f"الشاشة الأولى ليست «{expected}»: {' | '.join(texts[:6])}")
        # ينتظر حتى يتحكم عامل الخدمة بالصفحة ويحفظ الهيكل.
        # ينتظر حتى يثبَّت عامل الخدمة ويتحكم بالصفحة (clients.claim) بعد حفظ الهيكل.
        page.evaluate("() => navigator.serviceWorker.ready.then(() => true)")
        page.wait_for_function("() => navigator.serviceWorker.controller !== null", timeout=TIMEOUT_MS)
        outcome.service_worker = True
        page.wait_for_timeout(3000)
        page.screenshot(path=str(out_dir / f"{app}-online.png"))

        # دون إنترنت: يُفتح من جديد من ذاكرة الجهاز.
        context.set_offline(True)
        start = time.monotonic()
        page.reload(wait_until="load", timeout=TIMEOUT_MS)
        offline_texts = wait_for_text(page, expected)
        outcome.offline_ms = int((time.monotonic() - start) * 1000)
        if not any(expected in t for t in offline_texts):
            outcome.problems.append(
                f"دون إنترنت لم تظهر «{expected}»: {' | '.join(offline_texts[:6])}"
            )
        page.screenshot(path=str(out_dir / f"{app}-offline.png"))

        # الإدارة: «تجربة محلية بلا خادم» يشغّل التطبيق كله في المتصفح (القاعدة والخدمات وأول الشاشات)، فيُكشف كل ما
        # لا يعمل على الويب بعد الشاشة الأولى (مثل استعمال Platform الذي أظهر شاشة رمادية بعد الدخول).
        if app == "admin":
            context.set_offline(False)
            page.reload(wait_until="load", timeout=TIMEOUT_MS)
            wait_for_text(page, expected)
            button = page.locator("flt-semantics[role=button]", has_text=LOCAL_PREVIEW)
            if button.count() == 0:
                outcome.warnings.append(f"لا زر «{LOCAL_PREVIEW}» في الشاشة الأولى")
            else:
                button.first.click()
                deadline = time.monotonic() + TIMEOUT_MS / 1000
                started: list[str] = []
                while time.monotonic() < deadline:
                    page.wait_for_timeout(1000)
                    started = visible_texts(page)
                    if started and not any(expected in t for t in started):
                        break
                outcome.texts += ["— المحلي —", *started[:8]]
                if any(START_FAILED in t for t in started):
                    outcome.warnings.append(f"التشغيل المحلي فشل: «{START_FAILED}»")
                elif not started or any(expected in t for t in started):
                    outcome.warnings.append(
                        "التشغيل المحلي لم يتجاوز الشاشة الأولى: " + " | ".join(started[:6])
                    )
                page.screenshot(path=str(out_dir / f"{app}-local.png"))
    except Exception as error:  # noqa: BLE001 — يُسجَّل ويكمل الفحص
        outcome.problems.append(f"خطأ أثناء الفحص: {str(error).splitlines()[0][:200]}")
    finally:
        fatal = [e for e in errors if "ResizeObserver" not in e]
        if fatal:
            outcome.problems.append("أخطاء الصفحة: " + " | ".join(e[:160] for e in fatal[:3]))
        context.close()
    return outcome


def run(site: Path, out_dir: Path) -> int:
    from playwright.sync_api import sync_playwright

    out_dir.mkdir(parents=True, exist_ok=True)
    server, base = serve(site)
    outcomes: list[WebOutcome] = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            for app in FIRST_SCREENS:
                outcomes.append(smoke_app(browser, base, app, out_dir))
                last = outcomes[-1]
                print(f"{app}: {'ok' if last.ok else 'FAILED'} online={last.online_ms}ms offline={last.offline_ms}ms")
            browser.close()
    finally:
        server.shutdown()
    (out_dir / "summary.json").write_text(
        json.dumps([asdict(o) | {"ok": o.ok} for o in outcomes], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    for o in outcomes:
        for warning in o.warnings:
            print(f"::warning title=web-smoke-{o.app}-local::{warning}")
        if o.ok:
            print(f"::notice title=web-smoke-{o.app}::أول فتح {o.online_ms} م.ث، ودون إنترنت {o.offline_ms} م.ث")
        else:
            print(f"::error title=web-smoke-{o.app}::{' ؛ '.join(o.problems)}")
    return 0 if all(o.ok for o in outcomes) else 1


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    return run(Path(argv[1]), Path(argv[2]))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
