/// إعدادات الاتصال بالخادم: تُمرَّر وقت البناء بـ `--dart-define` (بناء مخصَّص
/// لمدرسة، أو بناء التطوير والاختبار)، أو تُقرأ من رمز الربط المحفوظ على
/// الجهاز ([SchoolPairing]) فتكون النسخة نفسها لكل المدارس. لا يُحفظ شيء منها
/// في المستودع (وهو عام).
///
/// ```text
/// flutter build apk --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<المفتاح العام>
/// ```
///
/// المفتاح العام (anon / publishable) مصمَّم ليُضمَّن في التطبيقات، وصلاحيات
/// البيانات يحميها RLS على الخادم لا سرّية هذا المفتاح.
class AppConfig {
  const AppConfig({
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
    this.schoolName = '',
  });

  /// الإعدادات المضمَّنة وقت البناء.
  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// اسم المدرسة كما في رمز الربط؛ فارغ في بناء مضمَّن. للعرض فقط.
  final String schoolName;

  /// هل الاتصال بالخادم مهيّأ؟ دونه يعمل التطبيق في الوضع المحلي.
  bool get isConfigured =>
      Uri.tryParse(supabaseUrl)?.hasAuthority == true &&
      supabaseUrl.startsWith('https://') &&
      supabaseAnonKey.isNotEmpty;

  /// مفتاح المدرسة: يُشتق من عنوان خادمها ويُلحَق باسم قاعدتها المحلية وصورها،
  /// فلا تختلط بيانات مدرستين على جهاز واحد مهما أُعيد الربط. فارغ دون خادم.
  String get schoolKey => schoolKeyOf(supabaseUrl);

  /// مفتاح المدرسة لعنوان خادم: أحرف وأرقام و`_` فقط فيصلح اسم ملف.
  static String schoolKeyOf(String url) {
    final uri = Uri.tryParse(url.trim());
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || host.isEmpty) return '';
    final port = uri.hasPort && uri.port != 443 ? '_${uri.port}' : '';
    return '${host.replaceAll(RegExp('[^a-z0-9]'), '_')}$port';
  }
}
