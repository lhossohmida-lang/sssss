import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// قائمة التلاميذ: بحث مفهرس بالاسم أو اللقب أو هاتف الوليّ، وتحميل مقسّم
/// (50 ثم 50 كلما اقتربت من نهاية القائمة)، وصور مصغّرة محلية.
class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  int _limit = StudentQueries.pageSize;

  /// آخر صفحة وصلت، تُعرض أثناء تحميل الصفحة التالية فلا تومض القائمة.
  StudentPage? _last;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    final page = _last;
    if (page == null || !page.hasMore) return;
    if (_scroll.position.extentAfter < 600 && page.items.length >= _limit) {
      setState(() => _limit += StudentQueries.pageSize);
    }
  }

  void _search(String value) {
    _debounce?.cancel();
    // مهلة قصيرة حتى لا يُعاد الاستعلام مع كل حرف.
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _limit = StudentQueries.pageSize;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final state = ref.watch(
      studentPageProvider((query: _query, limit: _limit)),
    );
    state.whenData((page) => _last = page);
    final page = state.value ?? _last;

    Widget body;
    if (page == null) {
      body = state.hasError
          ? ClayErrorView(
              message: 'تعذّرت قراءة التلاميذ من القاعدة المحلية',
              onRetry: () => ref.invalidate(studentPageProvider),
            )
          : const ClaySkeletonList();
    } else if (page.items.isEmpty) {
      body = ClayEmptyView(
        title: _query.isEmpty ? 'لا يوجد تلاميذ بعد' : 'لا نتائج مطابقة للبحث',
        message: _query.isEmpty
            ? 'يُسجَّل التلاميذ من استمارة التسجيل'
            : 'جرّب جزءاً من الاسم أو أول أرقام هاتف الوليّ',
        icon: ClayIcons.students,
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(
          horizontal: ClaySpacing.screenPadding,
        ),
        itemCount: page.items.length,
        itemExtent: 72,
        itemBuilder: (context, i) => _StudentTile(item: page.items[i]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ClaySpacing.screenPadding,
            ClaySpacing.sm,
            ClaySpacing.screenPadding,
            ClaySpacing.xs,
          ),
          child: ClayTextField(
            hint: 'ابحث بالاسم أو اللقب أو هاتف الوليّ',
            prefixIcon: ClayIcons.search,
            onChanged: _search,
          ),
        ),
        if (page != null && page.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
              vertical: ClaySpacing.xs,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _query.isEmpty ? '${page.total} تلميذ' : '${page.total} نتيجة',
                style: text.bodySmall!.copyWith(color: p.textMuted),
              ),
            ),
          ),
        Expanded(child: body),
      ],
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.item});

  final StudentListItem item;

  /// الصورة المصغّرة من المسار المحلي؛ دونه تظهر الأحرف الأولى.
  ImageProvider? get _photo {
    final path = item.student.photoLocalPath;
    return path == null || path.isEmpty ? null : FileImage(File(path));
  }

  @override
  Widget build(BuildContext context) {
    final phone = item.student.parentPhone;
    return ClayListTile(
      leading: ClayAvatar(name: item.fullName, image: _photo),
      title: item.fullName,
      subtitle: item.levelName == null ? phone : '${item.levelName} · $phone',
    );
  }
}
