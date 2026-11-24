import 'package:drift/wasm.dart';

/// عامل قاعدة نسخة الويب: يُترجَم إلى `drift_worker.js` بجانب `index.html` (مسار web في CI) فيشغّل SQLite
/// في خيط خلفي للمتصفح. يُبنى من drift نفسه المستعمل في التطبيق فيتطابق الإصداران.
void main() => WasmDatabase.workerMainForOpen();
