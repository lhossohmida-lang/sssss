/// تطبيع نص البحث العربي واللاتيني ومطابقته، ليجد المستخدم الاسم مهما اختلفت كتابته:
/// حركات التشكيل والتطويل، وصور الألف (أ إ آ)، والياء والألف المقصورة، والتاء المربوطة والهاء،
/// والأرقام الهندية واللاتينية، وحالة الأحرف اللاتينية.
abstract final class SearchText {
  static final RegExp _marks = RegExp('[ً-ٰٟـ]');
  static final RegExp _spaces = RegExp(r'\s+');

  /// النص بصيغة موحَّدة للمقارنة: أحرف صغيرة، دون تشكيل ولا تطويل، وبصور حروف موحَّدة.
  static String normalize(String value) {
    final buffer = StringBuffer();
    for (final unit in value.replaceAll(_marks, '').toLowerCase().runes) {
      buffer.write(_fold(unit));
    }
    return buffer.toString().replaceAll(_spaces, ' ').trim();
  }

  static String _fold(int rune) {
    switch (rune) {
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0622: // آ
      case 0x0671: // ٱ
        return 'ا';
      case 0x0649: // ى
      case 0x0626: // ئ
        return 'ي';
      case 0x0624: // ؤ
        return 'و';
      case 0x0629: // ة
        return 'ه';
    }
    // الأرقام الهندية (٠-٩) والفارسية (۰-۹) إلى لاتينية.
    if (rune >= 0x0660 && rune <= 0x0669) {
      return String.fromCharCode(0x30 + rune - 0x0660);
    }
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      return String.fromCharCode(0x30 + rune - 0x06F0);
    }
    return String.fromCharCode(rune);
  }

  /// هل يطابق [fields] نص البحث [query]؟ كل كلمة من البحث يجب أن ترد في أحد الحقول
  /// (بأي ترتيب). البحث الفارغ يطابق كل شيء.
  static bool matches(String query, Iterable<String?> fields) {
    final words = normalize(query).split(' ').where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final haystack = normalize(fields.whereType<String>().join(' '));
    return words.every(haystack.contains);
  }
}
