import 'enums.dart';
import 'money.dart';

/// حساب أسعار التلميذ. كل المبالغ بالدينار ومقرَّبة إلى أقرب 10.
abstract final class Pricing {
  /// سعر الدورة بعد التخفيض.
  static int netPrice({
    required int price,
    required DiscountType discountType,
    required int discountValue,
  }) {
    if (price < 0) throw ArgumentError.value(price, 'price', 'سعر سالب');
    switch (discountType) {
      case DiscountType.none:
        return Money.roundToTen(price);
      case DiscountType.percent:
        final percent = discountValue.clamp(0, 100);
        return Money.roundToTen(price * (100 - percent) / 100);
      case DiscountType.fixed:
        final net = price - discountValue;
        return Money.roundToTen(net < 0 ? 0 : net);
      case DiscountType.exempt:
        return 0;
    }
  }

  /// قيمة [sessions] حصة من دورة فيها [sessionsPerCycle] حصة بسعر [netPrice].
  ///
  /// تُستعمل لرصيد الغياب برخصة ورصيد الملتحق في منتصف الدورة.
  static int sessionsValue({
    required int netPrice,
    required int sessions,
    required int sessionsPerCycle,
  }) {
    if (sessionsPerCycle <= 0) {
      throw ArgumentError.value(sessionsPerCycle, 'sessionsPerCycle');
    }
    if (sessions <= 0) return 0;
    final capped = sessions > sessionsPerCycle ? sessionsPerCycle : sessions;
    return Money.roundToTen(netPrice * capped / sessionsPerCycle);
  }
}

/// عدد الحصص بصياغة عربية صحيحة: «حصة واحدة»، «حصتان»، «4 حصص»، «12 حصة».
abstract final class SessionCount {
  static String label(int count) {
    if (count == 1) return 'حصة واحدة';
    if (count == 2) return 'حصتان';
    return count >= 3 && count <= 10 ? '$count حصص' : '$count حصة';
  }
}

/// مستحق تلميذ في مجموعة عن دورة واحدة.
class CycleDue {
  const CycleDue({
    required this.studentId,
    required this.groupId,
    required this.cycleNumber,
    required this.netPrice,
    required this.credits,
    required this.paid,
    required this.exempt,
  });

  final String studentId;
  final String groupId;
  final int cycleNumber;

  /// السعر بعد التخفيض وقبل خصم الأرصدة.
  final int netPrice;

  /// مجموع الأرصدة المخصومة من هذه الدورة.
  final int credits;

  /// مجموع ما دُفع عن هذه الدورة.
  final int paid;

  /// هل التلميذ معفى كلياً في هذه المجموعة؟
  final bool exempt;

  /// الأرصدة المخصومة بالحصص: قيمتها مقسومة على سعر الحصة ([netPrice] ÷ [sessionsPerCycle])،
  /// مقرَّبة لأقرب حصة وبحدّ حصص الدورة. فملتحق في الحصة 5 من 8 دفع الشهر الأول كاملاً
  /// يظهر له في الشهر الثاني رصيد 4 حصص. صفر إن لم يكن رصيد أو سعر.
  int creditSessions(int sessionsPerCycle) {
    if (credits <= 0 || netPrice <= 0 || sessionsPerCycle <= 0) return 0;
    final sessions = (credits * sessionsPerCycle / netPrice).round();
    return sessions > sessionsPerCycle ? sessionsPerCycle : sessions;
  }

  /// المطلوب دفعه عن الدورة بعد خصم الأرصدة.
  int get due {
    final value = netPrice - credits;
    return value < 0 ? 0 : value;
  }

  /// الباقي غير المدفوع.
  int get remaining {
    final value = due - paid;
    return value < 0 ? 0 : value;
  }

  bool get isSettled => remaining == 0;
}
