import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// المستحقات: من عليهم مال من الدورات غير المسدَّدة، الأكثر مبلغاً أولاً،
/// مع بحث بالاسم أو هاتف الوليّ وحصر بمجموعة، وزر تسجيل دفعة لكل منهم.
class DuesScreen extends ConsumerStatefulWidget {
  const DuesScreen({super.key});

  @override
  ConsumerState<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends ConsumerState<DuesScreen> {
  Timer? _debounce;
  String _query = '';
  String? _groupId;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final groups = ref.watch(groupsProvider).value ?? const <GroupItem>[];
    final report = ref.watch(
      duesReportProvider((groupId: _groupId, query: _query)),
    );
    final canReceive = ref.can(
      PermissionModule.receiveMoney,
      PermissionAction.use,
    );

    return Scaffold(
      appBar: const ClayAppBar(title: 'المستحقات', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ClaySpacing.screenPadding,
              0,
              ClaySpacing.screenPadding,
              ClaySpacing.sm,
            ),
            child: ClayCard(
              flat: true,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      report.value == null
                          ? 'المستحقات'
                          : '${report.value!.count} تلميذ عليهم مستحقات',
                      style: text.titleSmall,
                    ),
                  ),
                  Text(
                    Money.format(report.value?.total ?? 0),
                    style: text.titleMedium!.copyWith(
                      color: (report.value?.total ?? 0) > 0
                          ? p.status.danger
                          : p.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: ClayTextField(
              hint: 'ابحث باسم التلميذ أو هاتف الوليّ',
              prefixIcon: ClayIcons.search,
              onChanged: _search,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: ClayDropdown<String?>(
              label: 'المجموعة',
              value: _groupId,
              options: [
                const ClayOption(value: null, label: 'كل المجموعات'),
                for (final g in groups)
                  ClayOption(
                    value: g.id,
                    label: 'المجموعة ${g.number} · ${g.subjectName}',
                  ),
              ],
              onChanged: (value) => setState(() => _groupId = value),
            ),
          ),
          Expanded(
            child: report.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّر حساب المستحقات',
                onRetry: () => ref.invalidate(duesReportProvider),
              ),
              data: (data) {
                if (data.isEmpty) {
                  final filtered = _query.isNotEmpty || _groupId != null;
                  return ClayEmptyView(
                    title: filtered ? 'لا نتائج مطابقة' : 'لا مستحقات',
                    message: filtered
                        ? 'جرّب اسماً آخر أو مجموعة أخرى'
                        : 'كل التلاميذ سدّدوا ما عليهم',
                    icon: ClayIcons.check,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  itemCount: data.students.length,
                  itemExtent: 112,
                  itemBuilder: (context, i) => _DueTile(
                    student: data.students[i],
                    canReceive: canReceive,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({required this.student, required this.canReceive});

  final DueStudent student;
  final bool canReceive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final first = student.lines.first;
    final more = student.lines.length - 1;
    return ClayListTile(
      title: student.name,
      subtitle:
          '${first.label}${more > 0 ? ' و$more أخرى' : ''}\n'
          '${student.parentPhone}',
      subtitleLines: 2,
      onTap: () => context.push('/students/${student.studentId}'),
      trailing: [
        Text(
          Money.format(student.total),
          style: text.titleSmall!.copyWith(color: p.status.danger),
        ),
        if (canReceive)
          IconButton(
            tooltip: 'تسجيل دفعة لـ ${student.name}',
            icon: const Icon(ClayIcons.payments),
            onPressed: () =>
                context.push('/payments/new?student=${student.studentId}'),
          ),
      ],
    );
  }
}
