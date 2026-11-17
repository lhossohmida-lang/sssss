import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  group('PhoneNumbers', () {
    test('يوحّد الصيغ المحلية والدولية', () {
      for (final raw in [
        '0550123456',
        '055 012 34 56',
        '0550-12-34-56',
        '(0550) 12.34.56',
        '+213550123456',
        '+213 550 12 34 56',
        '00213550123456',
      ]) {
        expect(PhoneNumbers.normalize(raw), '0550123456', reason: raw);
        expect(PhoneNumbers.isValid(raw), isTrue, reason: raw);
        expect(PhoneNumbers.toInternational(raw), '+213550123456');
      }
    });

    test('الأرقام العربية-الهندية والفارسية تصير لاتينية', () {
      expect(PhoneNumbers.normalize('٠٥٥٠١٢٣٤٥٦'), '0550123456');
      expect(PhoneNumbers.normalize('۰۶۶۱۲۳۴۵۶۷'), '0661234567');
      expect(PhoneNumbers.normalize('٠٦٦ ١٢٣ ٤٥ ٦٧'), '0661234567');
      expect(PhoneNumbers.isValid('٠٧٧٠٠٠٠٠٠٠'), isTrue);
    });

    test('علامات الاتجاه والمسافات الصفرية الخفية تُزال', () {
      expect(
        PhoneNumbers.normalize('\u{200E}0550123456\u{200F}'),
        '0550123456',
      );
      expect(
        PhoneNumbers.normalize('\u{202A}0550\u{200B}123456\u{202C}'),
        '0550123456',
      );
      expect(PhoneNumbers.normalize('\u{FEFF}0550123456'), '0550123456');
    });

    test('غير الصالح يُرفض', () {
      for (final raw in ['', '0150123456', '055012345', '05501234567', 'abc']) {
        expect(PhoneNumbers.isValid(raw), isFalse, reason: raw);
      }
      expect(() => PhoneNumbers.toInternational('abc'), throwsFormatException);
    });
  });
}
