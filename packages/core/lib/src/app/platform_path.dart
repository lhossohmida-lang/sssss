import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// فاصل المسارات على هذا النظام؛ في المتصفح (نسخة الويب) لا `Platform` فيُستعمل `/`.
String get platformPathSeparator => kIsWeb ? '/' : Platform.pathSeparator;
