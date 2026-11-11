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
    expect(Money.format(0), '0 دج');
    expect(Money.format(500), '500 دج');
    expect(Money.format(1500), '1 500 دج');
    expect(Money.format(12500), '12 500 دج');
    expect(Money.format(1250000), '1 250 000 دج');
    expect(Money.format(-2000), '-2 000 دج');
  });
}
