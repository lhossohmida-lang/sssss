import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  test('التقريب إلى أقرب 10 دج', () {
    expect(Money.roundToTen(1500), 1500);
    expect(Money.roundToTen(1504.9), 1500);
    expect(Money.roundToTen(1505), 1510);
    expect(Money.roundToTen(1506), 1510);
    expect(Money.roundToTen(0), 0);
    expect(Money.roundToTen(4), 0);
    expect(Money.roundToTen(666.67), 670);
  });

  test('المبلغ غير الصالح يرمي خطأ', () {
    expect(() => Money.roundToTen(double.nan), throwsArgumentError);
    expect(() => Money.roundToTen(double.infinity), throwsArgumentError);
  });

  test('التنسيق بفاصل الآلاف ورمز العملة', () {
    const nb = '\u{00A0}';
    expect(Money.format(0), '0 دج');
    expect(Money.format(500), '500 دج');
    expect(Money.format(1500), '1${nb}500 دج');
    expect(Money.format(12500), '12${nb}500 دج');
    expect(Money.format(1250000), '1${nb}250${nb}000 دج');
    expect(Money.format(-2000), '-2${nb}000 دج');
  });

  test('فاصل الآلاف مسافة غير منقسمة حتى لا تنقلب مجموعات الأرقام في السطر العربي', () {
    // المسافة العادية (U+0020) تقسم العدد في فقرة من اليمين إلى اليسار فيظهر
    // `1 500` هكذا `500 1`؛ وU+00A0 فئتها «فاصل مشترك» فيبقى العدد كتلة واحدة.
    expect(Money.thousandsSeparator.runes.single, 0x00A0);
    final amount = Money.format(1250000);
    expect(amount.split('\u{00A0}'), ['1', '250', '000 دج']);
    expect(amount.split(' '), ['1\u{00A0}250\u{00A0}000', 'دج']);
  });
}
