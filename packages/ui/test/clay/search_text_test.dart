import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';

void main() {
  group('SearchText.normalize', () {
    test('يوحّد صور الألف والياء والتاء المربوطة', () {
      expect(SearchText.normalize('أحمد إبراهيم آمنة'), 'احمد ابراهيم امنه');
      expect(SearchText.normalize('مصطفى'), 'مصطفي');
      expect(SearchText.normalize('فاطمة'), 'فاطمه');
      expect(SearchText.normalize('مسؤول'), 'مسوول');
      expect(SearchText.normalize('رئيس'), 'رييس');
    });

    test('يحذف التشكيل والتطويل ويوحّد المسافات والحالة', () {
      expect(SearchText.normalize('مُحَمَّد'), 'محمد');
      expect(SearchText.normalize('محـــمد'), 'محمد');
      expect(SearchText.normalize('  Ali   Ben  '), 'ali ben');
      expect(SearchText.normalize(''), '');
    });

    test('الأرقام الهندية والفارسية تصير لاتينية', () {
      expect(SearchText.normalize('الفوج ١٢'), 'الفوج 12');
      expect(SearchText.normalize('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    });
  });

  group('SearchText.matches', () {
    test('البحث الفارغ يطابق كل شيء', () {
      expect(SearchText.matches('', ['أحمد']), isTrue);
      expect(SearchText.matches('   ', const []), isTrue);
    });

    test('كل كلمة يجب أن ترد، بأي ترتيب، في أي حقل', () {
      const fields = ['أحمد بن علي', 'رياضيات'];
      expect(SearchText.matches('احمد', fields), isTrue);
      expect(SearchText.matches('علي احمد', fields), isTrue);
      expect(SearchText.matches('احمد رياضيات', fields), isTrue);
      expect(SearchText.matches('احمد فيزياء', fields), isFalse);
      expect(SearchText.matches('خالد', fields), isFalse);
    });

    test('تتجاهل الحقول الفارغة وتجد جزءاً من الكلمة', () {
      expect(SearchText.matches('رحم', ['عبد الرحمن', null]), isTrue);
      expect(SearchText.matches('12', ['الفوج 12 · رياضيات']), isTrue);
      expect(SearchText.matches('١٢', ['الفوج 12']), isTrue);
    });
  });
}
