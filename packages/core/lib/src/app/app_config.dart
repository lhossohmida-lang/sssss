/// إعدادات الاتصال بالخادم، تُمرَّر وقت البناء بـ `--dart-define` فلا يُحفظ
/// شيء منها في المستودع (وهو عام).
///
/// ```text
/// flutter build apk --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<المفتاح العام>
/// ```
///
/// المفتاح العام (anon / publishable) مصمَّم ليُضمَّن في التطبيقات، وصلاحيات
/// البيانات يحميها RLS على الخادم لا سرّية هذا المفتاح.
class AppConfig {
  const AppConfig({this.supabaseUrl = '', this.supabaseAnonKey = ''});

  /// الإعدادات المضمَّنة وقت البناء.
  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// هل الاتصال بالخادم مهيّأ؟ دونه يعمل التطبيق في الوضع المحلي.
  bool get isConfigured =>
      Uri.tryParse(supabaseUrl)?.hasAuthority == true &&
      supabaseUrl.startsWith('https://') &&
      supabaseAnonKey.isNotEmpty;
}
