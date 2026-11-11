import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:school_core/school_core.dart';

void main() {
  runApp(const AdminApp());
}

/// جذر تطبيق إدارة المدرسة.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  static const AppIdentity identity = AppIdentity.admin;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: identity.displayName,
      debugShowCheckedModeBanner: false,
      locale: AppIdentity.locale,
      supportedLocales: const [AppIdentity.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: Center(
          child: Text(
            identity.displayName,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
