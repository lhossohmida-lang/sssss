import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// يفتح ورقة لاختيار عدة تلاميذ من المسجَّلين من قبل، ببحث بالاسم أو اللقب أو هاتف الوليّ
/// (بالبداية كقائمة التلاميذ، فلا يمسح الجدول كله مهما كثروا). [exclude] معرّفات تُخفى
/// (منتسبو الفوج مثلاً). يعيد المختارين بترتيب اختيارهم، أو `null` عند الإغلاق دون إضافة.
Future<List<StudentListItem>?> pickExistingStudents(
  BuildContext context, {
  Set<String> exclude = const {},
  String title = 'إضافة تلاميذ موجودين',
  String confirmLabel = 'إضافة',
}) {
  return showClayBottomSheet<List<StudentListItem>>(
    context,
    title: title,
    builder: (_) =>
        _StudentMultiPicker(exclude: exclude, confirmLabel: confirmLabel),
  );
}

class _StudentMultiPicker extends ConsumerStatefulWidget {
  const _StudentMultiPicker({
    required this.exclude,
    required this.confirmLabel,
  });

  final Set<String> exclude;
  final String confirmLabel;

  @override
  ConsumerState<_StudentMultiPicker> createState() =>
      _StudentMultiPickerState();
}

class _StudentMultiPickerState extends ConsumerState<_StudentMultiPicker> {
  static const int _step = StudentQueries.pageSize;

  final _controller = TextEditingController();

  /// المحدَّدون بترتيب تحديدهم؛ يبقون محدَّدين عبر تغيير البحث.
  final Map<String, StudentListItem> _selected = {};
  Timer? _debounce;
  String _query = '';
  int _limit = _step;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _limit = _step;
      });
    });
  }

  void _toggle(StudentListItem item) => setState(() {
    if (_selected.remove(item.id) == null) _selected[item.id] = item;
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final page = ref.watch(studentPageProvider((query: _query, limit: _limit)));
    final height = (MediaQuery.sizeOf(context).height * 0.72).clamp(
      320.0,
      620.0,
    );
    final desktop = const {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(Theme.of(context).platform);
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClayTextField(
            controller: _controller,
            hint: 'ابحث بالاسم أو اللقب أو هاتف الوليّ',
            prefixIcon: ClayIcons.search,
            autofocus: desktop,
            onChanged: _onChanged,
          ),
          const SizedBox(height: ClaySpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selected.isEmpty
                      ? 'اضغط على تلميذ لتحديده'
                      : 'المحدَّد: ${_selected.length}',
                  style: text.bodySmall!.copyWith(color: p.textMuted),
                ),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('إلغاء التحديد'),
                ),
            ],
          ),
          Expanded(
            child: page.when(
              loading: () => const ClayLoadingView(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة التلاميذ',
                onRetry: () => ref.invalidate(studentPageProvider),
              ),
              data: (data) {
                final items = [
                  for (final item in data.items)
                    if (!widget.exclude.contains(item.id)) item,
                ];
                if (items.isEmpty && !data.hasMore) {
                  return ClayEmptyView(
                    title: _query.isEmpty
                        ? 'لا تلاميذ للإضافة'
                        : 'لا نتائج مطابقة للبحث',
                    message: _query.isEmpty
                        ? 'كل التلاميذ المسجَّلين في الفوج أصلاً'
                        : null,
                    icon: ClayIcons.students,
                  );
                }
                return ListView.builder(
                  itemCount: items.length + (data.hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: ClaySpacing.sm,
                        ),
                        child: ClayButton(
                          label: 'عرض المزيد',
                          kind: ClayButtonKind.secondary,
                          onPressed: () => setState(() => _limit += _step),
                        ),
                      );
                    }
                    final item = items[i];
                    final subtitle = [
                      if (item.levelName != null) item.levelName!,
                      'الوليّ ${item.student.parentPhone}',
                    ].join(' · ');
                    return InkWell(
                      borderRadius: BorderRadius.circular(ClayRadius.md),
                      onTap: () => _toggle(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ClaySpacing.xs,
                          vertical: ClaySpacing.sm,
                        ),
                        child: Row(
                          children: [
                            ClayCheckbox(
                              value: _selected.containsKey(item.id),
                              semanticLabel: item.fullName,
                              onChanged: (_) => _toggle(item),
                            ),
                            const SizedBox(width: ClaySpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.fullName, style: text.bodyLarge),
                                  Text(
                                    subtitle,
                                    style: text.bodySmall!.copyWith(
                                      color: p.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: ClaySpacing.sm),
          ClayButton(
            label: _selected.isEmpty
                ? widget.confirmLabel
                : '${widget.confirmLabel} (${_selected.length})',
            icon: ClayIcons.check,
            expand: true,
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.values.toList()),
          ),
        ],
      ),
    );
  }
}
