import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// صورة PNG صالحة للاختبارات بالحجم المطلوب (ألوان متدرجة).
Uint8List samplePngBytes({int width = 640, int height = 480}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
