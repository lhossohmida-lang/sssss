import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'phone.dart';

/// تلميذ في القائمة مع اسم مستواه.
class StudentListItem {
  const StudentListItem({required this.student, this.levelName});

  final StudentRow student;
  final String? levelName;

  String get id => student.id;
  String get fullName => '${student.firstName} ${student.lastName}';
}

/// صفحة من قائمة التلاميذ: ما حُمّل منها، والعدد الكلي المطابق للبحث.
class StudentPage {
  const StudentPage({required this.items, required this.total});

  final List<StudentListItem> items;

  /// عدد كل التلاميذ المطابقين، لا ما حُمّل فقط.
  final int total;

  bool get hasMore => items.length < total;
}

/// استعلامات قائمة التلاميذ: بحث مفهرس وتحميل مقسّم.
///
/// البحث بالبداية فقط (نطاق على عمود مفهرس `>= q AND < q+￿`) فلا يمسح
/// الجدول كله مهما كثر التلاميذ. ما يُكتب بكلمتين (الاسم واللقب بأي ترتيب)
/// يُطابق الاسم بإحداهما واللقب بالأخرى، والأرقام تُطابق بداية هاتف الوليّ.
class StudentQueries {
  StudentQueries(this.db);

  final AppDatabase db;

  /// حجم الصفحة الافتراضي.
  static const int pageSize = 50;

  /// صيغ الكلمة المدخلة للبحث بالبداية.
  ///
  /// الأسماء تُكتب بصيغ متفاوتة («أحمد» و«احمد»، «إيمان» و«ايمان»)، والفهرس
  /// على القيم كما كُتبت. فإن بدأت الكلمة بألف بأي شكل جُرّبت الأشكال الأربعة
  /// (ا أ إ آ) للحرف الأول، وهو موضع الاختلاف الشائع في البحث بالبداية.
  static List<String> variants(String token) {
    if (token.isEmpty) return const [''];
    const alefs = ['ا', 'أ', 'إ', 'آ'];
    final first = token.substring(0, 1);
    if (!alefs.contains(first)) return [token];
    final rest = token.substring(1);
    return [for (final alef in alefs) '$alef$rest'];
  }

  /// يبني شرط WHERE ومتغيراته لنص البحث [query]. بلا بحث: كل التلاميذ الأحياء.
  ({String where, List<Variable<Object>> vars}) _filter(String query) {
    final text = query.trim();
    const base = 's.deleted_at IS NULL';
    if (text.isEmpty) return (where: base, vars: const []);

    String range(String column, String prefix, List<Variable<Object>> vars) {
      vars
        ..add(Variable<String>(prefix))
        ..add(Variable<String>('$prefix￿'));
      return '($column >= ? AND $column < ?)';
    }

    final vars = <Variable<Object>>[];
    final tokens = text.split(RegExp(r'\s+'));
    final clauses = <String>[];
    final digits = PhoneNumbers.normalize(text);
    if (RegExp(r'^\d{2,}$').hasMatch(digits)) {
      clauses.add(range('s.parent_phone', digits, vars));
    } else if (tokens.length == 1) {
      for (final v in variants(tokens.first)) {
        clauses
          ..add(range('s.last_name', v, vars))
          ..add(range('s.first_name', v, vars));
      }
    } else {
      final a = tokens[0];
      final b = tokens[1];
      for (final x in variants(a)) {
        for (final y in variants(b)) {
          clauses
            ..add(
              '(${range('s.first_name', x, vars)} AND '
              '${range('s.last_name', y, vars)})',
            )
            ..add(
              '(${range('s.first_name', y, vars)} AND '
              '${range('s.last_name', x, vars)})',
            );
        }
      }
    }
    return (where: '$base AND (${clauses.join(' OR ')})', vars: vars);
  }

  /// أول [limit] تلميذاً مطابقاً للبحث مرتبين بالاسم، مع العدد الكلي.
  /// تتحدث القائمة مع كل تغيير في التلاميذ أو المستويات.
  Stream<StudentPage> watchPage({String query = '', int limit = pageSize}) {
    final filter = _filter(query);
    final list = db.customSelect(
      'SELECT s.*, l.name AS level_name FROM students s '
      'LEFT JOIN levels l ON l.id = s.level_id '
      'WHERE ${filter.where} ORDER BY s.last_name, s.first_name, s.id '
      'LIMIT ?',
      variables: [...filter.vars, Variable<int>(limit)],
      readsFrom: {db.students, db.levels},
    );
    final count = db.customSelect(
      'SELECT COUNT(*) AS n FROM students s WHERE ${filter.where}',
      variables: filter.vars,
      readsFrom: {db.students},
    );
    return list.watch().asyncMap((rows) async {
      final total = (await count.getSingle()).read<int>('n');
      return StudentPage(
        items: [
          for (final row in rows)
            StudentListItem(
              student: db.students.map(row.data),
              levelName: row.read<String?>('level_name'),
            ),
        ],
        total: total,
      );
    });
  }
}
