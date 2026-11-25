import 'enums.dart';
import 'money.dart';

/// من يتحمل تخفيض تلميذ أو إعفاءه: المدرسة، أم الأستاذ، أم مبلغ يحدده المدير للأستاذ.
enum DiscountBearer {
  /// الأستاذ يأخذ نصيبه كاملاً من مال المدرسة (ما يفعله النظام ما لم يُحدَّد غيره).
  school('school', 'المدرسة', 'الأستاذ يأخذ نصيبه كاملاً من مال المدرسة'),

  /// يُخصم التخفيض من نصيب الأستاذ: المدرسة تأخذ من حقه (وللإعفاء الكامل لا يأخذ شيئاً).
  teacher('teacher', 'الأستاذ', 'يُخصم التخفيض من نصيب الأستاذ'),

  /// الأستاذ يتحمّل التخفيض كله ويبقى للمدرسة نصيبها كاملاً: فلتلميذ مجاني لا يأخذ الأستاذ شيئاً
  /// ويُخصم من حقه نصيب المدرسة من سعر التلميذ (ما يأخذه سالب).
  teacherFull(
    'teacher_full',
    'الأستاذ، وللمدرسة نصيبها',
    'لا يأخذ الأستاذ عنه شيئاً ويُخصم من حقه نصيب المدرسة',
  ),

  /// يحدد المدير ما يأخذه الأستاذ عن هذا التلميذ.
  custom(
    'custom',
    'مبلغ أحدده للأستاذ',
    'أكتب ما يأخذه الأستاذ عن هذا التلميذ',
  );

  const DiscountBearer(this.code, this.label, this.help);

  final String code;
  final String label;
  final String help;
}

/// حساب أسعار التلميذ. كل المبالغ بالدينار ومقرَّبة إلى أقرب 10.
abstract final class Pricing {
  /// ما يأخذه الأستاذ عن تلميذ بحسب [bearer]: `null` يعني نصيبه في الفوج [rate] كاملاً.
  static int? teacherAmountFor(
    DiscountBearer bearer, {
    required int rate,
    required int price,
    required int net,
    int? custom,
  }) => switch (bearer) {
    DiscountBearer.school => null,
    DiscountBearer.teacher => teacherAmountWhenTeacherBears(
      rate: rate,
      price: price,
      net: net,
    ),
    DiscountBearer.teacherFull => Money.roundToTen(rate - (price - net)),
    DiscountBearer.custom => custom,
  };

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

  /// ما يأخذه الأستاذ عن تلميذ حين **يتحمل هو التخفيض**: نصيبه [rate] ناقصاً ما نقص من سعر التلميذ
  /// ([price] ناقصاً [net])، ولا ينزل عن صفر. فهامش المدرسة (السعر ناقص نصيب الأستاذ) لا يتغير،
  /// والإعفاء الكامل يُسقط نصيب الأستاذ كله إن بلغ التخفيض نصيبه.
  static int teacherAmountWhenTeacherBears({
    required int rate,
    required int price,
    required int net,
  }) {
    final reduction = price - net;
    final amount = rate - (reduction < 0 ? 0 : reduction);
    return Money.roundToTen(amount < 0 ? 0 : amount);
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

  /// عدد حصص الدورة التي يغطيها ما سُدِّد (المدفوع مع الأرصدة). كلها للمعفى أو من سعره صفر، ولا شيء
  /// لمن لم يسدّد شيئاً، وإلا بنسبة ما سُدِّد من السعر مقرَّباً إلى حصة كاملة نحو الأسفل.
  int coveredSessions(int sessionsPerCycle) {
    if (exempt || netPrice <= 0) return sessionsPerCycle;
    final settled = (credits > netPrice ? netPrice : credits) + paid;
    if (settled <= 0) return 0;
    if (settled >= netPrice) return sessionsPerCycle;
    return (settled * sessionsPerCycle) ~/ netPrice;
  }
}
