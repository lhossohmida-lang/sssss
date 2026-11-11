import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clay/clay_button.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';

/// الصورة المحفوظة على الجهاز من مسارها المحلي؛ `null` إن لم توجد صورة.
ImageProvider? localPhoto(String? path) =>
    path == null || path.isEmpty ? null : FileImage(File(path));

/// مصدر الصور: يلتقط صورة ويعيد بياناتها الخام (قبل الضغط)، أو `null` عند
/// الإلغاء. التطبيق الحقيقي كاميرا الهاتف أو كاميرا الحاسوب، وتُستبدل في
/// الاختبارات بنسخة وهمية.
abstract interface class PhotoSource {
  Future<Uint8List?> capture(BuildContext context);
}

/// الالتقاط بالكاميرا: كاميرا الهاتف على Android، وكاميرا الحاسوب الموصولة
/// (webcam) على Windows (الإجابة 40).
class CameraPhotoSource implements PhotoSource {
  const CameraPhotoSource();

  @override
  Future<Uint8List?> capture(BuildContext context) =>
      Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const CameraCaptureScreen(),
        ),
      );
}

final Provider<PhotoSource> photoSourceProvider = Provider<PhotoSource>(
  (ref) => const CameraPhotoSource(),
);

/// شاشة الالتقاط: معاينة حية، زر التقاط، تبديل الكاميرا عند وجود أكثر من
/// واحدة، ثم مراجعة الصورة («استعمال» أو «إعادة»).
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _index = 0;
  String? _error;
  bool _busy = false;
  Uint8List? _taken;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'لا توجد كاميرا على هذا الجهاز');
        return;
      }
      await _open(_index);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  Future<void> _open(int index) async {
    final old = _controller;
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    setState(() {
      _controller = null;
      _index = index;
    });
    await old?.dispose();
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = _describe(e));
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _error = null;
    });
  }

  String _describe(CameraException e) {
    final code = e.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return 'لم يُمنح إذن استعمال الكاميرا. فعّله من إعدادات الجهاز';
    }
    return 'تعذّر تشغيل الكاميرا (${e.code})';
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _taken = bytes);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final taken = _taken;
    final controller = _controller;

    Widget body;
    if (_error != null) {
      body = ClayErrorView(
        title: 'الكاميرا غير متاحة',
        message: _error!,
        onRetry: () {
          setState(() => _error = null);
          unawaited(_start());
        },
      );
    } else if (taken != null) {
      body = Center(child: Image.memory(taken, fit: BoxFit.contain));
    } else if (controller == null) {
      body = const ClayLoadingView(message: 'جارٍ تشغيل الكاميرا');
    } else {
      body = Center(child: CameraPreview(controller));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('التقاط صورة', style: text.titleLarge),
        leading: IconButton(
          tooltip: 'إغلاق',
          icon: const Icon(ClayIcons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: body),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(ClaySpacing.lg),
              child: taken != null
                  ? Row(
                      children: [
                        Expanded(
                          child: ClayButton(
                            label: 'استعمال الصورة',
                            icon: ClayIcons.check,
                            onPressed: () => Navigator.of(context).pop(taken),
                          ),
                        ),
                        const SizedBox(width: ClaySpacing.md),
                        Expanded(
                          child: ClayButton(
                            label: 'إعادة',
                            kind: ClayButtonKind.secondary,
                            onPressed: () => setState(() => _taken = null),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_cameras.length > 1)
                          IconButton(
                            tooltip: 'تبديل الكاميرا',
                            icon: Icon(
                              Icons.cameraswitch_rounded,
                              color: p.text,
                            ),
                            onPressed: _busy
                                ? null
                                : () => _open((_index + 1) % _cameras.length),
                          ),
                        ClayButton(
                          label: 'التقاط',
                          icon: ClayIcons.camera,
                          loading: _busy,
                          onPressed: controller == null ? null : _shoot,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// حقل صورة في النماذج: يعرض الصورة الحالية أو الملتقطة، ويلتقط أو يغيّر أو
/// يزيل. الصورة الملتقطة تبقى بيانات خاماً في [onChanged] وتُضغط وتُحفظ عند
/// حفظ النموذج بـ `PhotoService`.
class ClayPhotoField extends ConsumerWidget {
  const ClayPhotoField({
    required this.name,
    required this.onChanged,
    this.current,
    this.pending,
    this.enabled = true,
    super.key,
  });

  /// اسم صاحب الصورة (للأحرف الأولى إن لم توجد صورة).
  final String name;

  /// الصورة المحفوظة حالياً.
  final ImageProvider? current;

  /// الصورة الملتقطة ولم تُحفظ بعد.
  final Uint8List? pending;
  final ValueChanged<Uint8List?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = pending != null ? MemoryImage(pending!) : current;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClayAvatar(name: name, image: image, size: 72),
        const SizedBox(width: ClaySpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClayButton(
                label: image == null ? 'التقاط صورة' : 'تغيير الصورة',
                icon: ClayIcons.camera,
                kind: ClayButtonKind.secondary,
                expand: true,
                onPressed: enabled
                    ? () async {
                        final bytes = await ref
                            .read(photoSourceProvider)
                            .capture(context);
                        if (bytes != null) onChanged(bytes);
                      }
                    : null,
              ),
              if (pending != null)
                TextButton(
                  onPressed: enabled ? () => onChanged(null) : null,
                  child: const Text('إلغاء الصورة الملتقطة'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
