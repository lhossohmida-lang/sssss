import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// صلة نسخة الويب بالمتصفح: هل فُتحت من أيقونة الشاشة الرئيسية، وهل يتيح المتصفح التثبيت بضغطة
/// (`beforeinstallprompt` في Chrome وEdge على Android والحاسوب، يحفظه `index.html` في
/// `window.__pwaInstallPrompt`). Safari على iPhone لا يتيحه لأي موقع: يُثبَّت من «مشاركة».
class PwaBridge {
  const PwaBridge();

  bool get isStandalone {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    // Safari على iPhone: navigator.standalone.
    final standalone = web.window.navigator.getProperty<JSAny?>(
      'standalone'.toJS,
    );
    return standalone.isA<JSBoolean>() && (standalone! as JSBoolean).toDart;
  }

  bool get isIos {
    final agent = web.window.navigator.userAgent;
    if (RegExp('iPhone|iPad|iPod').hasMatch(agent)) return true;
    // iPad الحديث يعرّف نفسه «Macintosh» مع شاشة لمس.
    return agent.contains('Macintosh') &&
        web.window.navigator.maxTouchPoints > 1;
  }

  /// لغة المتصفح، وهي على iPhone لغة الجهاز نفسها التي تُكتب بها أزرار Safari.
  String get language => web.window.navigator.language;

  JSObject? get _prompt {
    final value = globalContext.getProperty<JSAny?>('__pwaInstallPrompt'.toJS);
    return value.isA<JSObject>() ? value! as JSObject : null;
  }

  bool get canPrompt => _prompt != null;

  /// يعرض نافذة التثبيت التي يتيحها المتصفح؛ `true` إن قبلها المستخدم.
  Future<bool> prompt() async {
    final event = _prompt;
    if (event == null) return false;
    globalContext.setProperty('__pwaInstallPrompt'.toJS, null);
    event.callMethod<JSAny?>('prompt'.toJS);
    final choice = event.getProperty<JSAny?>('userChoice'.toJS);
    if (!choice.isA<JSPromise>()) return false;
    final result = await (choice! as JSPromise<JSObject>).toDart;
    final outcome = result.getProperty<JSAny?>('outcome'.toJS);
    return outcome.isA<JSString>() &&
        (outcome! as JSString).toDart == 'accepted';
  }

  /// يُبلَّغ حين يتيح المتصفح التثبيت أو يتم التثبيت (أحداث يرسلها `index.html`).
  Stream<void> get changes {
    // يُغلق مع إلغاء آخر مستمع (onCancel).
    // ignore: close_sinks
    final controller = StreamController<void>.broadcast();
    void fire(web.Event _) => controller.add(null);
    final listener = fire.toJS;
    controller
      ..onListen = () {
        web.window.addEventListener('pwa-install-available', listener);
        web.window.addEventListener('appinstalled', listener);
      }
      ..onCancel = () {
        web.window.removeEventListener('pwa-install-available', listener);
        web.window.removeEventListener('appinstalled', listener);
      };
    return controller.stream;
  }
}
