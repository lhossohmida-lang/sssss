import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_chat/school_chat.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_inputs.dart';
import '../clay/clay_navigation.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'file_picking.dart';
import 'list_page.dart';
import 'pdf_viewer.dart';
import 'providers.dart';

/// قائمة المحادثات؛ تلخص آخر رسالة والرسائل غير المقروءة لكل غرفة.
class ChatInboxScreen extends ConsumerStatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final rooms = ref.watch(chatRoomsProvider(ChatService.pageSize));
    final canStart = session != null && _canStartChat(session);
    return Scaffold(
      appBar: ClayAppBar(
        title: 'المحادثات',
        actions: [
          if (canStart)
            IconButton(
              tooltip: 'محادثة جديدة',
              onPressed: () => context.push('/chat/new'),
              icon: const Icon(Icons.add_comment_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ClaySpacing.screenPadding,
              ClaySpacing.xs,
              ClaySpacing.screenPadding,
              ClaySpacing.sm,
            ),
            child: ClayTextField(
              hint: 'ابحث في المحادثات',
              prefixIcon: Icons.search_rounded,
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: rooms.when(
              loading: () => const ClayLoadingView(),
              error: (error, _) => ClayErrorView(
                message: 'تعذّر تحميل المحادثات',
                onRetry: () =>
                    ref.invalidate(chatRoomsProvider(ChatService.pageSize)),
              ),
              data: (items) {
                final query = _query.toLowerCase();
                final filtered = items
                    .where(
                      (room) =>
                          query.isEmpty ||
                          room.title.toLowerCase().contains(query) ||
                          (room.latestMessage ?? '').toLowerCase().contains(
                            query,
                          ),
                    )
                    .toList(growable: false);
                if (filtered.isEmpty) {
                  return ClayEmptyView(
                    title: query.isEmpty
                        ? 'لا توجد محادثات بعد'
                        : 'لا توجد نتائج لهذا البحث',
                    message: query.isEmpty
                        ? 'ابدأ محادثة مع وليّ أو أستاذ، أو افتح غرفة مجموعتك'
                        : 'جرّب اسماً أو كلمة من آخر رسالة',
                    icon: ClayIcons.chat,
                    actionLabel: canStart ? 'بدء محادثة' : null,
                    onAction: canStart ? () => context.push('/chat/new') : null,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  itemCount: filtered.length,
                  itemExtent: 88,
                  itemBuilder: (context, index) => _ChatRoomTile(
                    room: filtered[index],
                    onTap: () => context.push(
                      '/chat/${Uri.encodeComponent(filtered[index].id)}',
                    ),
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

class _ChatRoomTile extends StatelessWidget {
  const _ChatRoomTile({required this.room, required this.onTap});

  final ChatRoomListItem room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGroup = room.type == ChatRoomType.group;
    final subtitle = room.latestMessage?.trim().isNotEmpty == true
        ? room.latestMessage!
        : (isGroup ? 'غرفة جماعية' : 'ابدأ المحادثة');
    return ClayListTile(
      title: room.title.isEmpty ? 'محادثة خاصة' : room.title,
      subtitle: subtitle,
      leading: ClayAvatar(name: room.title, size: 48),
      trailing: [
        if (room.muted)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: ClaySpacing.xs),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 18,
              color: context.palette.textMuted,
            ),
          ),
        if (room.unreadCount > 0)
          ClayBadge(
            label: room.unreadCount > 99 ? '99+' : '${room.unreadCount}',
            tone: ClayTone.info,
          ),
        const SizedBox(width: ClaySpacing.xs),
        Icon(
          isGroup ? Icons.groups_rounded : Icons.chevron_left_rounded,
          color: context.palette.textMuted,
        ),
      ],
      onTap: onTap,
    );
  }
}

/// إنشاء محادثة خاصة مع جهة اتصال مسموحة أو فتح غرفة مجموعة.
class ChatCreateScreen extends ConsumerStatefulWidget {
  const ChatCreateScreen({super.key});

  @override
  ConsumerState<ChatCreateScreen> createState() => _ChatCreateScreenState();
}

class _ChatCreateScreenState extends ConsumerState<ChatCreateScreen> {
  String _query = '';
  String? _openingId;

  Future<void> _openPrivate(ChatContact contact) async {
    if (_openingId != null) return;
    setState(() => _openingId = contact.accountId);
    try {
      final room = await ref
          .read(chatServiceProvider)
          .createPrivateRoom(contact.accountId);
      if (mounted) {
        context.go('/chat/${Uri.encodeComponent(room.id)}');
      }
    } on Object catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _openGroup(GroupItem group) async {
    if (_openingId != null) return;
    setState(() => _openingId = group.id);
    try {
      final room = await ref
          .read(chatServiceProvider)
          .createGroupRoom(group.id);
      if (mounted) {
        context.go('/chat/${Uri.encodeComponent(room.id)}');
      }
    } on Object catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is ChatAccessException
        ? error.message
        : 'تعذّر إنشاء المحادثة';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    if (session == null || !_canStartChat(session)) {
      return const Scaffold(
        appBar: ClayAppBar(title: 'محادثة جديدة', showBack: true),
        body: ClayEmptyView(
          title: 'لا توجد صلاحية لبدء محادثة',
          message: 'تواصل مع الإدارة لتفعيل صلاحية المحادثات',
        ),
      );
    }
    final service = ref.watch(chatServiceProvider);
    final canCreateGroups =
        session.role == UserRole.teacher || service.principal.canCreateAny;
    final tabs = canCreateGroups ? 2 : 1;
    return DefaultTabController(
      length: tabs,
      child: Scaffold(
        appBar: const ClayAppBar(title: 'محادثة جديدة', showBack: true),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ClaySpacing.screenPadding,
                ClaySpacing.xs,
                ClaySpacing.screenPadding,
                ClaySpacing.sm,
              ),
              child: ClayTextField(
                hint: 'ابحث بالاسم',
                prefixIcon: Icons.search_rounded,
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            TabBar(
              tabs: [
                const Tab(text: 'محادثة خاصة'),
                if (canCreateGroups) const Tab(text: 'غرفة مجموعة'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _privateContacts(),
                  if (canCreateGroups) _groupRooms(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _privateContacts() {
    final contacts = ref.watch(
      chatContactsProvider((query: _query, limit: ChatService.pageSize)),
    );
    return contacts.when(
      loading: () => const ClayLoadingView(),
      error: (error, _) => ClayErrorView(
        message: 'تعذّر تحميل جهات الاتصال',
        onRetry: () => ref.invalidate(
          chatContactsProvider((query: _query, limit: ChatService.pageSize)),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const ClayEmptyView(
            title: 'لا توجد جهات اتصال مطابقة',
            message: 'تظهر هنا حسابات الأولياء والأساتذة المرتبطة بمجموعاتك',
            icon: Icons.person_search_outlined,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: ClaySpacing.screenPadding,
          ),
          itemCount: items.length,
          itemExtent: 84,
          itemBuilder: (context, index) {
            final contact = items[index];
            return ClayListTile(
              title: contact.displayName,
              subtitle: _roleName(contact.role),
              leading: ClayAvatar(name: contact.displayName),
              trailing: [
                if (_openingId == contact.accountId)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.chevron_left_rounded),
              ],
              onTap: _openingId == null ? () => _openPrivate(contact) : null,
            );
          },
        );
      },
    );
  }

  Widget _groupRooms() {
    final groups = ref.watch(groupsProvider);
    return groups.when(
      loading: () => const ClayLoadingView(),
      error: (error, _) => ClayErrorView(
        message: 'تعذّر تحميل المجموعات',
        onRetry: () => ref.invalidate(groupsProvider),
      ),
      data: (items) {
        final query = _query.toLowerCase();
        final filtered = items
            .where(
              (item) =>
                  query.isEmpty ||
                  _groupTitle(item).toLowerCase().contains(query) ||
                  item.teacherName.toLowerCase().contains(query),
            )
            .toList(growable: false);
        if (filtered.isEmpty) {
          return const ClayEmptyView(
            title: 'لا توجد مجموعات نشطة',
            message: 'ستظهر هنا مجموعاتك التي يمكن فتح غرفة محادثة لها',
            icon: ClayIcons.groups,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: ClaySpacing.screenPadding,
          ),
          itemCount: filtered.length,
          itemExtent: 88,
          itemBuilder: (context, index) {
            final group = filtered[index];
            return ClayListTile(
              title: _groupTitle(group),
              subtitle: '${group.teacherName} · ${group.studentCount} تلاميذ',
              leading: const Icon(ClayIcons.groups),
              trailing: [
                if (_openingId == group.id)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.chevron_left_rounded),
              ],
              onTap: _openingId == null ? () => _openGroup(group) : null,
            );
          },
        );
      },
    );
  }
}

/// محادثة لحظية مع إرسال متفائل وتحميل الرسائل الأقدم عند الطلب.
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({required this.roomId, super.key});

  final String roomId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<ChatMessageRow> _page = const [];
  bool _hasMore = false;
  bool _loadingPage = true;
  bool _sending = false;
  bool _loadingAttachment = false;
  bool _sendingText = false;
  int _lastAutoReadAt = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearHistoryStart);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_markRead());
      unawaited(_loadInitialPage());
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll
      ..removeListener(_nearHistoryStart)
      ..dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    try {
      await ref.read(chatServiceProvider).markRead(widget.roomId);
    } on Object {
      // The room stream presents access loss; opening the view should not crash.
    }
  }

  Future<void> _loadInitialPage() async {
    try {
      final page = await ref
          .read(chatServiceProvider)
          .loadMessages(widget.roomId);
      if (!mounted) return;
      setState(() {
        _page = page.messages;
        _hasMore = page.hasMore;
        _loadingPage = false;
      });
    } on Object {
      if (mounted) setState(() => _loadingPage = false);
    }
  }

  void _nearHistoryStart() {
    if (!_scroll.hasClients || !_hasMore || _loadingPage) return;
    final position = _scroll.position;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 72) {
      unawaited(_loadOlder());
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingPage || !_hasMore || _page.isEmpty) return;
    setState(() => _loadingPage = true);
    try {
      final first = _page.first;
      final next = await ref
          .read(chatServiceProvider)
          .loadMessages(
            widget.roomId,
            before: ChatMessageCursor(createdAt: first.createdAt, id: first.id),
          );
      if (!mounted) return;
      setState(() {
        _page = [...next.messages, ..._page];
        _hasMore = next.hasMore;
      });
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _loadingPage = false);
    }
  }

  List<ChatMessageRow> _mergeMessages(List<ChatMessageRow> live) {
    final byId = <String, ChatMessageRow>{
      for (final message in _page) message.id: message,
      for (final message in live) message.id: message,
    };
    return byId.values.toList()..sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }

  Future<void> _sendText() async {
    final text = _composer.text.trim();
    if (_sending || text.isEmpty) return;
    setState(() {
      _sending = true;
      _sendingText = true;
    });
    try {
      await ref.read(chatServiceProvider).sendText(widget.roomId, text);
      _composer.clear();
      await _markRead();
    } on Object catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingText = false;
        });
      }
    }
  }

  Future<void> _pickAttachment() async {
    if (_sending) return;
    String? stagedPath;
    var queued = false;
    setState(() => _loadingAttachment = true);
    try {
      final picked = await ref
          .read(fileSourceProvider)
          .pick(
            context,
            extensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
          );
      if (picked == null || !mounted) return;
      if (picked.bytes.length > ChatService.maximumAttachmentBytes) {
        _showMessage('الحد الأقصى لحجم المرفق 10 ميغابايت');
        return;
      }
      final runtime = ref.read(runtimeProvider);
      final directory = Directory(
        '${runtime.photosDirectory.path}${Platform.pathSeparator}chat_attachments',
      );
      await directory.create(recursive: true);
      final extension = _safeExtension(picked.name);
      final local = File(
        '${directory.path}${Platform.pathSeparator}'
        '${runtime.writer.newId()}.$extension',
      );
      stagedPath = local.path;
      await local.writeAsBytes(picked.bytes, flush: true);
      final image = const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension);
      setState(() {
        _sending = true;
        _sendingText = false;
      });
      await ref
          .read(chatServiceProvider)
          .sendMessage(
            widget.roomId,
            content: _composer.text,
            attachmentName: picked.name,
            attachmentType: image
                ? ChatAttachmentType.image
                : ChatAttachmentType.file,
            attachmentLocalPath: local.path,
            attachmentSizeBytes: picked.bytes.length,
          );
      queued = true;
      _composer.clear();
      await _markRead();
    } on Object catch (error) {
      if (stagedPath != null && !queued) {
        try {
          await File(stagedPath).delete();
        } on FileSystemException {
          // The file may not have been created before the failure.
        }
      }
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _loadingAttachment = false;
        });
      }
    }
  }

  Future<void> _toggleMuted(bool muted) async {
    try {
      await ref
          .read(chatServiceProvider)
          .setMuted(widget.roomId, muted: !muted);
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _openAttachment(ChatMessageRow message) async {
    Uint8List? bytes;
    final localPath = message.attachmentLocalPath;
    if (localPath != null) {
      try {
        final file = File(localPath);
        if (await file.exists()) bytes = await file.readAsBytes();
      } on FileSystemException {
        bytes = null;
      }
    }
    if (bytes == null && message.attachmentUrl != null) {
      final store = ref.read(runtimeProvider).fileStore;
      final slash = message.attachmentUrl!.indexOf('/');
      if (store != null && slash > 0) {
        try {
          bytes = await store.download(
            bucket: message.attachmentUrl!.substring(0, slash),
            remotePath: message.attachmentUrl!.substring(slash + 1),
          );
        } on Object {
          bytes = null;
        }
      }
    }
    if (!mounted) return;
    if (bytes == null) {
      _showMessage('تعذّر فتح المرفق؛ تحقّق من الاتصال ثم أعد المحاولة');
      return;
    }
    final name = message.attachmentName ?? 'مرفق';
    final extension = _safeExtension(name);
    if (extension == 'pdf') {
      await ref
          .read(pdfPresenterProvider)
          .show(context, bytes: bytes, fileName: name, title: name);
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) =>
            Dialog(child: InteractiveViewer(child: Image.memory(bytes!))),
      );
    }
  }

  void _showError(Object error) {
    final message = error is ChatAccessException
        ? error.message
        : 'تعذّر تنفيذ العملية؛ حاول مرة أخرى';
    _showMessage(message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(chatRoomProvider(widget.roomId));
    final messagesKey = (roomId: widget.roomId, limit: ChatService.pageSize);
    final messagesState = ref.watch(chatMessagesProvider(messagesKey));
    final session = ref.watch(sessionProvider).value;
    if (session != null) {
      ref.listen(chatMessagesProvider(messagesKey), (previous, next) {
        final messages = next.value;
        if (messages == null || messages.isEmpty) return;
        final latest = messages.last;
        if (latest.senderId != session.accountId &&
            latest.createdAt > _lastAutoReadAt) {
          _lastAutoReadAt = latest.createdAt;
          unawaited(_markRead());
        }
      });
    }
    return roomState.when(
      loading: () => const Scaffold(
        appBar: ClayAppBar(title: 'المحادثة', showBack: true),
        body: ClayLoadingView(),
      ),
      error: (error, _) => Scaffold(
        appBar: const ClayAppBar(title: 'المحادثة', showBack: true),
        body: _accessError(error),
      ),
      data: (room) {
        if (room == null) {
          return const Scaffold(
            appBar: ClayAppBar(title: 'المحادثة', showBack: true),
            body: ClayEmptyView(
              title: 'الغرفة غير موجودة',
              message: 'ربما أُغلقت أو لم تعد متاحة لحسابك',
            ),
          );
        }
        final membership = ref.watch(chatMembershipProvider(widget.roomId));
        final muted = membership.value?.muted ?? false;
        final canSend = _canSend(session, membership);
        return Scaffold(
          appBar: ClayAppBar(
            title: room.title.isEmpty ? 'محادثة خاصة' : room.title,
            showBack: true,
            actions: [
              IconButton(
                tooltip: muted ? 'إلغاء كتم المحادثة' : 'كتم المحادثة',
                onPressed: membership.value == null
                    ? null
                    : () => _toggleMuted(muted),
                icon: Icon(
                  muted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (room.isClosed) const _ClosedRoomNotice(),
              Expanded(
                child: messagesState.when(
                  loading: () => _loadingPage && _page.isNotEmpty
                      ? _messageList(_page, session?.accountId, room.type)
                      : const ClayLoadingView(),
                  error: (error, _) => _accessError(error),
                  data: (live) {
                    final messages = _mergeMessages(live);
                    if (messages.isEmpty) {
                      return const ClayEmptyView(
                        title: 'ابدأ الحديث',
                        message: 'ستظهر الرسائل هنا فور إرسالها',
                        icon: ClayIcons.chat,
                      );
                    }
                    return _messageList(
                      messages,
                      session?.accountId,
                      room.type,
                    );
                  },
                ),
              ),
              if (!room.isClosed) _composerBar(enabled: canSend),
            ],
          ),
        );
      },
    );
  }

  Widget _messageList(
    List<ChatMessageRow> messages,
    String? accountId,
    String roomType,
  ) => ListView.builder(
    controller: _scroll,
    reverse: true,
    padding: const EdgeInsets.fromLTRB(
      ClaySpacing.screenPadding,
      ClaySpacing.sm,
      ClaySpacing.screenPadding,
      ClaySpacing.md,
    ),
    itemCount: messages.length + 1,
    itemBuilder: (context, index) {
      if (index == messages.length) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: ClaySpacing.sm),
          child: Center(
            child: TextButton.icon(
              onPressed: _hasMore && !_loadingPage ? _loadOlder : null,
              icon: _loadingPage
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history_rounded),
              label: Text(_hasMore ? 'تحميل الأقدم' : 'بداية المحادثة'),
            ),
          ),
        );
      }
      final message = messages[messages.length - 1 - index];
      return _ChatMessageBubble(
        message: message,
        own: message.senderId == accountId,
        showSender: roomType == ChatRoomType.group.code,
        onAttachmentTap: () => _openAttachment(message),
      );
    },
  );

  Widget _composerBar({required bool enabled}) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaySpacing.screenPadding,
        ClaySpacing.xs,
        ClaySpacing.screenPadding,
        ClaySpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'إرفاق صورة أو PDF',
            onPressed: enabled && !_sending ? _pickAttachment : null,
            icon: _loadingAttachment
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file_rounded),
          ),
          Expanded(
            child: ClayTextField(
              controller: _composer,
              hint: 'اكتب رسالة…',
              maxLines: 4,
              maxLength: 10000,
              enabled: enabled && !_sending,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: ClaySpacing.xs),
          IconButton.filled(
            tooltip: 'إرسال',
            onPressed: enabled && !_sending && _composer.text.trim().isNotEmpty
                ? _sendText
                : null,
            icon: _sending && _sendingText
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    ),
  );

  bool _canSend(AuthSession? session, AsyncValue<ChatMemberRow?> membership) {
    if (session == null || membership.hasError) return false;
    return session.role == UserRole.owner ||
        session.can(PermissionModule.chat, PermissionAction.edit) ||
        membership.value != null;
  }

  Widget _accessError(Object error) {
    if (error is ChatAccessException) {
      return ClayEmptyView(
        title: error.message,
        message: 'ارجع إلى قائمة المحادثات لتحديث الغرف المتاحة',
        icon: Icons.lock_outline_rounded,
      );
    }
    return ClayErrorView(
      message: 'تعذّر تحميل رسائل المحادثة',
      onRetry: () {
        ref.invalidate(chatRoomProvider(widget.roomId));
        ref.invalidate(
          chatMessagesProvider((
            roomId: widget.roomId,
            limit: ChatService.pageSize,
          )),
        );
      },
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    required this.message,
    required this.own,
    required this.showSender,
    required this.onAttachmentTap,
  });

  final ChatMessageRow message;
  final bool own;
  final bool showSender;
  final VoidCallback onAttachmentTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = message.attachmentName;
    final hasAttachment = name != null && name.isNotEmpty;
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: own
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: own
                  ? palette.accent.withValues(alpha: 0.16)
                  : palette.surface,
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(ClayRadius.lg),
                topEnd: const Radius.circular(ClayRadius.lg),
                bottomStart: Radius.circular(
                  own ? ClayRadius.sm : ClayRadius.lg,
                ),
                bottomEnd: Radius.circular(own ? ClayRadius.lg : ClayRadius.sm),
              ),
              border: Border.all(
                color: palette.outline.withValues(alpha: 0.45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(ClaySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showSender)
                    Padding(
                      padding: const EdgeInsets.only(bottom: ClaySpacing.xs),
                      child: Text(
                        own
                            ? 'أنت'
                            : _roleName(_roleFromCode(message.senderRole)),
                        style: text.labelSmall!.copyWith(color: palette.accent),
                      ),
                    ),
                  if (message.content.isNotEmpty)
                    Text(message.content, style: text.bodyMedium),
                  if (hasAttachment) ...[
                    if (message.content.isNotEmpty)
                      const SizedBox(height: ClaySpacing.xs),
                    _AttachmentTile(
                      name: name,
                      image:
                          message.attachmentType ==
                          ChatAttachmentType.image.code,
                      onTap: onAttachmentTap,
                    ),
                  ],
                  const SizedBox(height: ClaySpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _timeText(message.createdAt),
                        style: text.labelSmall!.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.name,
    required this.image,
    required this.onTap,
  });

  final String name;
  final bool image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(ClayRadius.md),
    child: ClayContainer.flat(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.sm,
        vertical: ClaySpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            image ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
            color: context.palette.accent,
          ),
          const SizedBox(width: ClaySpacing.sm),
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: ClaySpacing.xs),
          const Icon(Icons.open_in_new_rounded, size: 16),
        ],
      ),
    ),
  );
}

class _ClosedRoomNotice extends StatelessWidget {
  const _ClosedRoomNotice();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(ClaySpacing.sm),
    child: ClayBadge(
      label: 'أُغلقت هذه المحادثة؛ يمكنك قراءة الرسائل السابقة فقط',
      tone: ClayTone.warning,
      icon: Icons.lock_outline_rounded,
    ),
  );
}

bool _canStartChat(AuthSession session) =>
    session.role == UserRole.owner ||
    session.role == UserRole.teacher ||
    session.role == UserRole.parent ||
    session.can(PermissionModule.chat, PermissionAction.add) ||
    session.can(PermissionModule.chat, PermissionAction.edit);

String _roleName(UserRole role) => switch (role) {
  UserRole.owner => 'الإدارة',
  UserRole.worker => 'عامل الإدارة',
  UserRole.teacher => 'أستاذ',
  UserRole.parent => 'وليّ',
};

UserRole _roleFromCode(String code) => UserRole.values.firstWhere(
  (role) => role.code == code,
  orElse: () => UserRole.parent,
);

String _groupTitle(GroupItem group) =>
    '${group.subjectName} · المجموعة ${group.number}';

String _safeExtension(String name) {
  final last = name.split('.').last.toLowerCase();
  return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(last) ? last : 'bin';
}

String _timeText(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(
    millis,
    isUtc: true,
  ).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}
