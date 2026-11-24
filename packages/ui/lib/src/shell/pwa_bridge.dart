// المتصفح وحده يعرف هل التطبيق مثبّت على الشاشة الرئيسية وكيف يُثبَّت؛ على الهاتف والحاسوب لا شيء.
export 'pwa_bridge_stub.dart'
    if (dart.library.js_interop) 'pwa_bridge_web.dart';
