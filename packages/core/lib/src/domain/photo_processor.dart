import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// ضغط الصور قبل حفظها ورفعها: أطول ضلع 600 بكسل وجودة JPEG 70% (الاقتراح
/// 65 يحدد 10MB حداً أقصى للملف، وصورة التلميذ بهذا الحجم تبقى نحو 40KB).
///
/// العملية ثقيلة (فك ترميز صورة الكاميرا كاملة)، فتجري في isolate خلفي ولا
/// تُجمّد الواجهة.
abstract final class PhotoProcessor {
  static const int maxSide = 600;
  static const int quality = 70;

  /// أكبر ملف مدخل مقبول (الاقتراح 65).
  static const int maxInputBytes = 10 * 1024 * 1024;

  /// يضغط [bytes] (JPEG أو PNG أو غيرهما مما تفكّه مكتبة الصور) ويعيد JPEG.
  ///
  /// - يُصحَّح اتجاه الصورة من بيانات EXIF (صور الهاتف الجانبية).
  /// - لا تُكبَّر الصور الأصغر من [maxSide].
  ///
  /// يرمي [FormatException] إن لم تكن البيانات صورة صالحة، أو تجاوزت
  /// [maxInputBytes].
  static Future<Uint8List> compress(
    Uint8List bytes, {
    int maxSide = PhotoProcessor.maxSide,
    int quality = PhotoProcessor.quality,
  }) {
    if (bytes.isEmpty) {
      return Future.error(const FormatException('الصورة فارغة'));
    }
    if (bytes.length > maxInputBytes) {
      return Future.error(
        const FormatException('حجم الصورة أكبر من 10 ميغابايت'),
      );
    }
    return Isolate.run(() => compressSync(bytes, maxSide, quality));
  }

  /// النسخة المتزامنة؛ تُستدعى داخل isolate (وعامة ليُختبر منطقها مباشرة).
  static Uint8List compressSync(Uint8List bytes, int maxSide, int quality) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('الملف ليس صورة صالحة');
    }
    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: maxSide,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: maxSide,
              interpolation: img.Interpolation.average,
            );
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
}
