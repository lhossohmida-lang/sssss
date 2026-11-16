import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase db;
  late SupabaseClient client;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    client = SupabaseClient('https://abc.supabase.co', 'sb_publishable_test');
  });
  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  test('المخزن البعيد يرسل المفتاح العام لا قيمة فارغة', () {
    // مكتبة Supabase لا تضع apikey في `rest.headers` (تضيفه لكل طلب في طبقتها)،
    // فقراءته منها أرسلت مفتاحاً فارغاً ورفض الخادم كل طلب مزامنة بـ401.
    expect(client.rest.headers['apikey'], isNull);
    final backend = SupabaseBackend(
      client,
      db: db,
      apiKey: 'sb_publishable_test',
    );
    expect(
      (backend.remote as PostgrestRemoteStore).apiKey,
      'sb_publishable_test',
    );
  });

  test('مفتاح فارغ يُرفض عند البناء بدل أن يفشل كل طلب بـ401', () {
    for (final key in ['', '   ']) {
      expect(
        () => SupabaseBackend(client, db: db, apiKey: key),
        throwsArgumentError,
      );
    }
  });
}
