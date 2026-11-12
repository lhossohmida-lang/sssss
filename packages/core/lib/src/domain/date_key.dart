/// التواريخ تُخزَّن نصاً بصيغة `YYYY-MM-DD` وأوقات اليوم بالدقائق.
abstract final class DateKey {
  /// مفتاح التاريخ ليوم [date] (بالتوقيت المحلي للجهاز).
  static String of(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// يحوّل المفتاح إلى تاريخ عند منتصف الليل.
  static DateTime parse(String key) {
    final parts = key.split('-');
    if (parts.length != 3) {
      throw FormatException('تاريخ غير صالح', key);
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// اليوم التالي لـ [key].
  static String next(String key) {
    final date = parse(key);
    return of(DateTime(date.year, date.month, date.day + 1));
  }

  /// رقم يوم الأسبوع: 1 = الاثنين … 7 = الأحد.
  static int weekday(String key) => parse(key).weekday;

  static const List<String> _monthNames = [
    'جانفي',
    'فيفري',
    'مارس',
    'أفريل',
    'ماي',
    'جوان',
    'جويلية',
    'أوت',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  /// اسم الشهر ([month] من 1 إلى 12) بالتسمية الجزائرية.
  static String monthName(int month) => _monthNames[month - 1];

  /// «نوفمبر 2026» من مفتاح الشهر `YYYY-MM`.
  static String monthLabel(String key) {
    final parts = key.split('-');
    return '${monthName(int.parse(parts[1]))} ${parts[0]}';
  }

  /// مفتاح الشهر `YYYY-MM` بعد [delta] شهراً من [key].
  static String shiftMonth(String key, int delta) {
    final parts = key.split('-');
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]) + delta);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}';
  }

  /// دقائق اليوم منذ منتصف الليل للوقت [time].
  static int minutesOf(DateTime time) => time.hour * 60 + time.minute;

  /// ينسّق الدقائق بصيغة `HH:MM`.
  static String formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
