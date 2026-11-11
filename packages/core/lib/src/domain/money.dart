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

  /// ينسّق المبلغ بفاصل للآلاف مع رمز العملة، مثل `12 500 دج`.
  static String format(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final sign = amount < 0 ? '-' : '';
    return '$sign$buffer $currency';
  }
}
