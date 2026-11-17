/// يتحقق من استعلام يكتبه النموذج قبل تنفيذه على القاعدة المحلية: SELECT واحد، للقراءة
/// فقط، على جداول مسموحة لهذا الحساب، بسقف للصفوف.
///
/// لا يعتمد على فحص نحوي كامل؛ يمرّ على الكلمات خارج النصوص فيمنع كل ما ليس قراءة
/// (DML وDDL وPRAGMA وATTACH ...) وأي إشارة إلى جدول ليس مسموحاً (في FROM أو JOIN أو استعلام
/// فرعي أو CTE) أو إلى عمود محجوب. أي شك يُرفض برسالة عربية يفهمها النموذج فيصحّح استعلامه.
class ReadOnlySql {
  ReadOnlySql({
    required this.allowedTables,
    required this.knownTables,
    this.hiddenColumns = const {},
  });

  /// أقصى صفوف تُعاد للنموذج.
  static const int maxRows = 100;

  /// أقصى طول للاستعلام.
  static const int maxLength = 4000;

  /// جداول يحق لهذا الحساب قراءتها.
  final Set<String> allowedTables;

  /// كل جداول القاعدة (ما خرج عن [allowedTables] منها محجوب).
  final Set<String> knownTables;

  /// أعمدة لا تُقرأ أبداً (رموز QR وروابط الملفات ومعرّفات المصادقة).
  final Set<String> hiddenColumns;

  /// كلمات تدل على غير القراءة أو على ما يستهلك الجهاز.
  static const Set<String> _forbidden = {
    'insert',
    'update',
    'delete',
    'drop',
    'create',
    'alter',
    'attach',
    'detach',
    'pragma',
    'vacuum',
    'reindex',
    'analyze',
    'begin',
    'commit',
    'rollback',
    'savepoint',
    'release',
    'explain',
    'recursive',
    'load_extension',
    'zeroblob',
    'randomblob',
    'readfile',
    'writefile',
    'returning',
  };

  /// النص الآمن الذي يُنفَّذ: الاستعلام داخل استعلام فرعي بسقف صفوف (مع صف زائد لمعرفة الاقتطاع).
  /// يرمي [ArgumentError] برسالة عربية إن لم يكن الاستعلام مقبولاً.
  String prepare(String sql) {
    var text = sql.trim();
    while (text.endsWith(';')) {
      text = text.substring(0, text.length - 1).trimRight();
    }
    if (text.isEmpty) throw ArgumentError('اكتب استعلام SELECT');
    if (text.length > maxLength) {
      throw ArgumentError('الاستعلام أطول من $maxLength حرفاً');
    }
    final words = _words(text);
    if (words.isEmpty || (words.first != 'select' && words.first != 'with')) {
      throw ArgumentError('يُسمح باستعلام SELECT واحد للقراءة فقط');
    }
    for (final word in words) {
      if (_forbidden.contains(word) ||
          word.startsWith('pragma_') ||
          word.startsWith('sqlite_')) {
        throw ArgumentError('الكلمة «$word» غير مسموحة: القراءة فقط');
      }
      if (hiddenColumns.contains(word)) {
        throw ArgumentError('العمود «$word» محجوب');
      }
      if (knownTables.contains(word) && !allowedTables.contains(word)) {
        throw ArgumentError('الجدول «$word» غير متاح لهذا الحساب');
      }
    }
    return 'SELECT * FROM ($text) LIMIT ${maxRows + 1}';
  }

  /// الكلمات خارج النصوص بأحرف صغيرة. يرفض التعليقات والفاصلة المنقوطة (استعلامات متعددة)
  /// و`replace` حين لا تكون دالة نصية.
  List<String> _words(String text) {
    final words = <String>[];
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c == "'") {
        i = _skipQuoted(text, i, "'");
        continue;
      }
      if (c == '"' || c == '`') {
        final end = _skipQuoted(text, i, c);
        words.add(text.substring(i + 1, end - 1).toLowerCase());
        i = end;
        continue;
      }
      if (c == '[') {
        final close = text.indexOf(']', i + 1);
        if (close < 0) throw ArgumentError('اقتباس غير مغلق في الاستعلام');
        words.add(text.substring(i + 1, close).toLowerCase());
        i = close + 1;
        continue;
      }
      if (c == '-' && i + 1 < text.length && text[i + 1] == '-') {
        throw ArgumentError('التعليقات غير مسموحة في الاستعلام');
      }
      if (c == '/' && i + 1 < text.length && text[i + 1] == '*') {
        throw ArgumentError('التعليقات غير مسموحة في الاستعلام');
      }
      if (c == ';') throw ArgumentError('استعلام واحد فقط في كل مرة');
      if (_isWordStart(c)) {
        var j = i + 1;
        while (j < text.length && _isWordPart(text[j])) {
          j++;
        }
        final word = text.substring(i, j).toLowerCase();
        if (word == 'replace') {
          var k = j;
          while (k < text.length && text[k].trim().isEmpty) {
            k++;
          }
          if (k >= text.length || text[k] != '(') {
            throw ArgumentError('الكلمة «replace» غير مسموحة: القراءة فقط');
          }
        }
        words.add(word);
        i = j;
        continue;
      }
      i++;
    }
    return words;
  }

  /// موضع ما بعد الاقتباس الذي يبدأ عند [start] ويُغلق بـ[quote] (والتكرار يعني حرفاً).
  static int _skipQuoted(String text, int start, String quote) {
    var i = start + 1;
    while (i < text.length) {
      if (text[i] == quote) {
        if (i + 1 < text.length && text[i + 1] == quote) {
          i += 2;
          continue;
        }
        return i + 1;
      }
      i++;
    }
    throw ArgumentError('اقتباس غير مغلق في الاستعلام');
  }

  static bool _isWordStart(String c) => RegExp('[A-Za-z_]').hasMatch(c);

  static bool _isWordPart(String c) => RegExp('[A-Za-z0-9_]').hasMatch(c);
}
