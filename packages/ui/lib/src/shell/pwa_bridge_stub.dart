/// خارج المتصفح: التطبيق مثبّت أصلاً، فلا بطاقة تثبيت.
class PwaBridge {
  const PwaBridge();

  bool get isStandalone => true;
  bool get isIos => false;
  bool get canPrompt => false;

  /// لغة المتصفح (رمز ISO مثل `ar` أو `fr-FR`).
  String get language => 'ar';
  Future<bool> prompt() async => false;
  Stream<void> get changes => const Stream.empty();
}
