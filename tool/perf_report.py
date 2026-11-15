#!/usr/bin/env python3
"""يحوّل نتيجة قياس الإطارات (frame_timings.json) إلى جدول في ملخص التشغيل
وإلى تعليقات `::notice` يمكن قراءتها من الواجهة العامة لـGitHub.

الاستعمال: python3 tool/perf_report.py apps/admin/build/frame_timings.json
"""
import json
import os
import sys

SCREENS = {
    "students_list": "قائمة التلاميذ",
    "groups_list": "قائمة المجموعات",
    "payments_list": "قائمة المدفوعات",
    "dashboard": "لوحة المدير",
}

COLUMNS = [
    ("frame_count", "إطارات"),
    ("average_frame_build_time_millis", "بناء: متوسط"),
    ("90th_percentile_frame_build_time_millis", "بناء: 90"),
    ("99th_percentile_frame_build_time_millis", "بناء: 99"),
    ("worst_frame_build_time_millis", "بناء: أسوأ"),
    ("average_frame_rasterizer_time_millis", "رسم: متوسط"),
    ("90th_percentile_frame_rasterizer_time_millis", "رسم: 90"),
    ("99th_percentile_frame_rasterizer_time_millis", "رسم: 99"),
    ("worst_frame_rasterizer_time_millis", "رسم: أسوأ"),
    ("missed_frame_build_budget_count", "فاتت البناء"),
    ("missed_frame_rasterizer_budget_count", "فاتت الرسم"),
]


def fmt(value):
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.1f}"
    return str(value)


def main(path):
    # المخرجات عربية: UTF-8 صريحاً (وحدة تحكم Windows الافتراضية لا تدعمها).
    sys.stdout.reconfigure(encoding="utf-8")
    if not os.path.exists(path):
        print(f"::error title=perf-report::الملف {path} غير موجود؛ لم يكتب الاختبار نتيجة")
        return 1
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)

    lines = ["## زمن الإطارات على محاكي Android (وضع debug)", ""]
    info = data.get("data", {})
    if info:
        lines.append(
            "البيانات: {students} تلميذ، {groups} مجموعة، {sessions} حصة، "
            "{attendance} سجل حضور، {payments} دفعة، {sms_messages} رسالة "
            "(توليدها {generation_millis}ms).".format(**{k: info.get(k, "?") for k in (
                "students", "groups", "sessions", "attendance", "payments",
                "sms_messages", "generation_millis")})
        )
        lines.append("")
    header = "| الشاشة | " + " | ".join(label for _, label in COLUMNS) + " |"
    lines.append(header)
    lines.append("|" + "---|" * (len(COLUMNS) + 1))
    for key, title in SCREENS.items():
        row = data.get(key)
        if not isinstance(row, dict):
            lines.append(f"| {title} | " + " | ".join("-" for _ in COLUMNS) + " |")
            continue
        lines.append(
            f"| {title} | "
            + " | ".join(fmt(row.get(column)) for column, _ in COLUMNS)
            + " |"
        )
        summary = ", ".join(
            f"{label}={fmt(row.get(column))}" for column, label in COLUMNS
        )
        print(f"::notice title=perf-{key}::{summary}")
    lines.append("")
    lines.append("الأزمنة بالمللي ثانية. ميزانية الإطار 16.7ms عند 60Hz.")

    text = "\n".join(lines)
    print(text)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "apps/admin/build/frame_timings.json"))
