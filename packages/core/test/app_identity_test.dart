import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  test('لكل تطبيق اسم حزمة فريد يبدأ بـ dz.school', () {
    final ids = AppIdentity.values.map((a) => a.packageId).toSet();
    expect(ids, hasLength(AppIdentity.values.length));
    expect(ids.every((id) => id.startsWith('dz.school.')), isTrue);
  });

  test('لغة الواجهة هي العربية', () {
    expect(AppIdentity.locale.languageCode, 'ar');
  });
}
