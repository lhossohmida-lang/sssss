/// المبالغ تُخزَّن أعداداً صحيحة بالدينار الجزائري.
library;

/// أدوات المال: التقريب والتنسيق.
abstract final class Money {
  /// رمز العملة الظاهر في الواجهة.
  static const String currency = 'دج';

  /// يقرّب المبلغ إلى أقرب 10 دج (النصف يُقرَّب للأعلى).
  static int roundToTen(num amount) {
    if (amount.isNaN || amount.isInfinite) {
      throw ArgumentError.value(amount, 'amount', 'مبلغ غير صالح');
    }
    return ((amount / 10) + 0.5).floor() * 10;
  }

  /// فاصل الآلاف: مسافة غير منقسمة (U+00A0). المسافة العادية بين مجموعتي أرقام في سطر
  /// عربي تقسم العدد إلى كتلتين تُرتَّبان من اليمين فيُقرأ `1 500` هكذا `500 1`؛ أما
  /// هذه المسافة ففئتها الثنائية «فاصل مشترك» فيبقى العدد كتلة واحدة تُقرأ من اليسار
  /// إلى اليمين كما يُكتب، ولا ينكسر السطر في وسطه.
  static const String thousandsSeparator = '\u{00A0}';

  /// ينسّق المبلغ بفاصل للآلاف مع رمز العملة، مثل `12 500 دج` (الفاصل [thousandsSeparator]).
  static String format(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(thousandsSeparator);
      }
      buffer.write(digits[i]);
    }
    final sign = amount < 0 ? '-' : '';
    return '$sign$buffer $currency';
  }
}
