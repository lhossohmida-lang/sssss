/// قطع SQL مشتركة لوسم الأفواج.
///
/// ترقيم الأفواج لكل مادة وسنة (فوج 1، فوج 2 ضمن «رياضيات 3 ثانوي») يجعل «الفوج 1 · رياضيات»
/// يتكرر في مستويين؛ فيُوسم الفوج في القوائم باسم مادته مع مستواها: «رياضيات (3 ثانوي)».
abstract final class GroupSql {
  /// اسم المادة مع اسم مستواها إن كان لها مستوى، ودون تكراره إن كان الاسم يحويه. تفترض أن
  /// جدول المواد بالاسم المستعار `sub`.
  static const String subjectLabel =
      '(CASE WHEN sub.level_id IS NULL THEN sub.name ELSE '
      'COALESCE((SELECT CASE WHEN instr(sub.name, lv.name) > 0 THEN sub.name '
      "ELSE sub.name || ' (' || lv.name || ')' END FROM levels lv "
      'WHERE lv.id = sub.level_id AND lv.deleted_at IS NULL), sub.name) END)';
}
