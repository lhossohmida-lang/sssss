/// خارج المتصفح: التطبيق مثبّت أصلاً، فلا بطاقة تثبيت.
class PwaBridge {
  const PwaBridge();

  bool get isStandalone => true;
  bool get isIos => false;
  bool get canPrompt => false;
  Future<bool> prompt() async => false;
  Stream<void> get changes => const Stream.empty();
}
