import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import 'pdf_viewer.dart';
import 'providers.dart';

/// «2026-11-14 10:30» من وقت بالمللي ثانية (بالتوقيت المحلي).
String paymentDateText(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${DateKey.of(t)} $hh:$mm';
}

/// بيانات الوصل من الدفعة: اسم المدرسة وعنوانها وهاتفها وشعارها من الإعدادات.
Future<ReceiptData> receiptData(WidgetRef ref, PaymentDetail detail) async {
  final settings = await ref.read(settingsServiceProvider).load();
  final logoFile = await ref.read(logoServiceProvider).resolve();
  final payment = detail.payment;
  return ReceiptData(
    schoolName: settings.schoolName.isEmpty ? 'المدرسة' : settings.schoolName,
    schoolAddress: settings.schoolAddress,
    schoolPhone: settings.schoolPhone,
    receiptNumber: payment.receiptNumber,
    dateText: paymentDateText(payment.createdAt),
    studentName: detail.item.studentName,
    description: detail.item.description,
    amount: payment.amount,
    remaining: detail.remaining,
    receivedByName: detail.receivedByName,
    note: payment.note,
    logo: logoFile == null ? null : await logoFile.readAsBytes(),
  );
}

/// يبني الوصل PDF بمقاس A5 ويعرضه للمعاينة والطباعة والمشاركة.
Future<void> showReceipt(
  BuildContext context,
  WidgetRef ref,
  PaymentDetail detail,
) async {
  final data = await receiptData(ref, detail);
  final font = await rootBundle.load(
    'packages/school_ui/assets/fonts/Cairo.ttf',
  );
  final bytes = await ReceiptPdf.build(
    data,
    fontData: font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
  );
  if (!context.mounted) return;
  await ref
      .read(pdfPresenterProvider)
      .show(
        context,
        bytes: bytes,
        fileName: 'receipt-${detail.payment.receiptNumber}.pdf',
        title: 'وصل ${detail.payment.receiptNumber}',
      );
}
