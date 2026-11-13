import 'package:drift/drift.dart';
import 'package:school_core/school_core.dart';

/// هوية الجلسة التي تُستخدم للتحقق من حدود المحادثة.
class ChatPrincipal {
  const ChatPrincipal({
    required this.userId,
    required this.role,
    required this.policy,
    this.entityId,
  });

  factory ChatPrincipal.fromSession(AuthSession session) => ChatPrincipal(
    userId: session.accountId,
    role: session.role,
    entityId: session.entityId,
    policy: session.policy,
  );

  final String userId;
  final UserRole role;
  final String? entityId;
  final AccessPolicy policy;

  bool get canViewAll =>
      role == UserRole.owner ||
      policy.can(PermissionModule.chat, PermissionAction.view) ||
      policy.can(PermissionModule.chat, PermissionAction.edit);

  bool get canManage =>
      role == UserRole.owner ||
      policy.can(PermissionModule.chat, PermissionAction.edit);

  bool get canDeleteAny =>
      canManage ||
      (canViewAll &&
          policy.can(PermissionModule.chat, PermissionAction.delete));

  bool get canCreateAny =>
      role == UserRole.owner ||
      policy.can(PermissionModule.chat, PermissionAction.add) ||
      policy.can(PermissionModule.chat, PermissionAction.edit);
}

/// خطأ صلاحية أو حالة محادثة غير قابلة للعمل.
class ChatAccessException implements Exception {
  const ChatAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// جهة يمكن فتح محادثة خاصة معها.
class ChatContact {
  const ChatContact({
    required this.accountId,
    required this.role,
    required this.entityId,
    required this.displayName,
  });

  final String accountId;
  final UserRole role;
  final String? entityId;
  final String displayName;
}

/// ملخص محادثة للقائمة، مع آخر رسالة وعدّاد غير المقروء.
class ChatRoomListItem {
  const ChatRoomListItem({
    required this.id,
    required this.type,
    required this.groupId,
    required this.title,
    required this.createdBy,
    required this.isClosed,
    required this.lastMessageAt,
    required this.latestMessage,
    required this.latestSenderId,
    required this.unreadCount,
    required this.muted,
  });

  final String id;
  final ChatRoomType type;
  final String? groupId;
  final String title;
  final String createdBy;
  final bool isClosed;
  final int? lastMessageAt;
  final String? latestMessage;
  final String? latestSenderId;
  final int unreadCount;
  final bool muted;
}

/// مؤشر صفحة الرسائل الأقدم.
class ChatMessageCursor {
  const ChatMessageCursor({required this.createdAt, required this.id});

  final int createdAt;
  final String id;
}

/// دفعة رسائل مرتبة من الأقدم إلى الأحدث لعرض المحادثة.
class ChatMessagePage {
  const ChatMessagePage({
    required this.messages,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<ChatMessageRow> messages;
  final bool hasMore;
  final ChatMessageCursor? nextCursor;
}

/// أنواع المرفقات المخزنة في `chat_messages.attachment_type`.
enum ChatAttachmentType {
  image('image'),
  file('file');

  const ChatAttachmentType(this.code);

  final String code;
}

/// خدمة المحادثات: صلاحيات الأطراف، التخزين المحلي، والإرسال المتفائل.
class ChatService {
  ChatService(this.db, this.writer, this.principal);

  static const int pageSize = 50;
  static const int maximumAttachmentBytes = 10 * 1024 * 1024;

  final AppDatabase db;
  final SyncWriter writer;
  final ChatPrincipal principal;

  bool get _canSendAsModerator =>
      principal.role == UserRole.owner ||
      principal.policy.can(PermissionModule.chat, PermissionAction.edit);

  /// جهات الاتصال المسموح بدء محادثة خاصة معها.
  ///
  /// الأستاذ يرى أولياء تلاميذ مجموعاته النشطة، والوليّ يرى أساتذة مجموعات
  /// أبنائه النشطة، والعامل يحتاج صلاحية إضافة أو تعديل المحادثات.
  Future<List<ChatContact>> privateContacts({
    String query = '',
    int limit = pageSize,
  }) async {
    _validateLimit(limit);
    final escapedQuery =
        '${query.trim().replaceAll('%', '').replaceAll('_', '')}%';
    late final String sql;
    late final List<Variable<Object>> variables;

    if (principal.canCreateAny) {
      sql =
          'SELECT id, role, entity_id, display_name FROM user_accounts '
          'WHERE deleted_at IS NULL AND id <> ? AND display_name LIKE ? '
          'ORDER BY display_name, id LIMIT ?';
      variables = [
        Variable<String>(principal.userId),
        Variable<String>(escapedQuery),
        Variable<int>(limit),
      ];
    } else if (principal.role == UserRole.teacher &&
        principal.entityId != null) {
      sql =
          'SELECT DISTINCT ua.id, ua.role, ua.entity_id, ua.display_name '
          'FROM user_accounts ua '
          'JOIN students s ON s.parent_account_id = ua.entity_id '
          'JOIN group_students gs ON gs.student_id = s.id '
          'AND gs.deleted_at IS NULL AND gs.left_at IS NULL '
          'JOIN groups g ON g.id = gs.group_id AND g.deleted_at IS NULL '
          'AND g.archived_at IS NULL '
          'WHERE ua.role = ? AND ua.deleted_at IS NULL AND s.deleted_at IS NULL '
          'AND g.teacher_id = ? AND ua.id <> ? AND ua.display_name LIKE ? '
          'ORDER BY ua.display_name, ua.id LIMIT ?';
      variables = [
        Variable<String>(UserRole.parent.code),
        Variable<String>(principal.entityId!),
        Variable<String>(principal.userId),
        Variable<String>(escapedQuery),
        Variable<int>(limit),
      ];
    } else if (principal.role == UserRole.parent &&
        principal.entityId != null) {
      sql =
          'SELECT DISTINCT ua.id, ua.role, ua.entity_id, ua.display_name '
          'FROM user_accounts ua '
          'JOIN groups g ON g.teacher_id = ua.entity_id '
          'AND g.deleted_at IS NULL AND g.archived_at IS NULL '
          'JOIN group_students gs ON gs.group_id = g.id '
          'AND gs.deleted_at IS NULL AND gs.left_at IS NULL '
          'JOIN students s ON s.id = gs.student_id AND s.deleted_at IS NULL '
          'WHERE ua.role = ? AND ua.deleted_at IS NULL '
          'AND s.parent_account_id = ? AND ua.id <> ? AND ua.display_name LIKE ? '
          'ORDER BY ua.display_name, ua.id LIMIT ?';
      variables = [
        Variable<String>(UserRole.teacher.code),
        Variable<String>(principal.entityId!),
        Variable<String>(principal.userId),
        Variable<String>(escapedQuery),
        Variable<int>(limit),
      ];
    } else {
      return const [];
    }

    final rows = await db
        .customSelect(
          sql,
          variables: variables,
          readsFrom: {
            db.userAccounts,
            db.students,
            db.groups,
            db.groupStudents,
          },
        )
        .get();
    return [
      for (final row in rows)
        ChatContact(
          accountId: row.read<String>('id'),
          role: UserRole.fromCode(row.read<String>('role')),
          entityId: row.read<String?>('entity_id'),
          displayName: row.read<String>('display_name'),
        ),
    ];
  }

  /// يفتح محادثة خاصة أو يعيد الموجودة بين الحسابين.
  Future<ChatRoomRow> createPrivateRoom(
    String targetAccountId, {
    String? title,
  }) async {
    _requireWriterActor();
    if (targetAccountId == principal.userId) {
      throw const ChatAccessException('لا يمكن بدء محادثة مع الحساب نفسه');
    }
    final target = await _account(targetAccountId);
    if (!await _canMessage(target)) {
      throw const ChatAccessException(
        'لا توجد مجموعة نشطة مشتركة تتيح هذه المحادثة',
      );
    }
    final roomId = StableId.chatPrivateRoom(principal.userId, targetAccountId);
    final naturalRoom =
        await (db.select(db.chatRooms)
              ..where((row) => row.id.equals(roomId) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (naturalRoom != null) return naturalRoom;

    final existing = await db
        .customSelect(
          'SELECT r.id FROM chat_rooms r '
          'WHERE r.type = ? AND r.deleted_at IS NULL '
          'AND EXISTS (SELECT 1 FROM chat_members a WHERE a.room_id = r.id '
          'AND a.user_id = ? AND a.deleted_at IS NULL) '
          'AND EXISTS (SELECT 1 FROM chat_members b WHERE b.room_id = r.id '
          'AND b.user_id = ? AND b.deleted_at IS NULL) '
          'ORDER BY r.is_closed ASC, '
          'COALESCE(r.last_message_at, r.created_at) DESC, r.id LIMIT 1',
          variables: [
            Variable<String>(ChatRoomType.private.code),
            Variable<String>(principal.userId),
            Variable<String>(targetAccountId),
          ],
          readsFrom: {db.chatRooms, db.chatMembers},
        )
        .getSingleOrNull();
    if (existing != null) {
      return _room(existing.read<String>('id'));
    }

    final now = writer.now();
    await writer.save(
      db.chatRooms,
      ChatRoomsCompanion.insert(
        id: roomId,
        createdAt: now,
        updatedAt: now,
        type: ChatRoomType.private.code,
        title: Value(
          title?.trim().isNotEmpty == true ? title!.trim() : target.displayName,
        ),
        createdBy: principal.userId,
      ),
      key: {'id': roomId},
    );
    await _ensureMember(roomId, principal.userId, principal.role.code);
    await _ensureMember(roomId, target.id, target.role);
    return _room(roomId);
  }

  /// ينشئ غرفة للمجموعة أو يحدّث أعضاءها بأولياء التلاميذ الحاليين.
  ///
  /// ينشئها صاحب المدرسة أو العامل المصرح له أو أستاذ المجموعة. عند إعادة
  /// وجود الغرفة المغلقة يحافظ على قرار الإغلاق ولا يعيد فتحها.
  Future<ChatRoomRow> createGroupRoom(String groupId, {String? title}) async {
    _requireWriterActor();
    final group =
        await (db.select(db.groups)..where(
              (row) =>
                  row.id.equals(groupId) &
                  row.deletedAt.isNull() &
                  row.archivedAt.isNull(),
            ))
            .getSingleOrNull();
    if (group == null) {
      throw const ChatAccessException('المجموعة غير موجودة أو مؤرشفة');
    }
    final isGroupTeacher =
        principal.role == UserRole.teacher &&
        principal.entityId == group.teacherId;
    if (!principal.canCreateAny && !isGroupTeacher) {
      throw const ChatAccessException('إنشاء غرفة هذه المجموعة غير مسموح');
    }

    final existing =
        await (db.select(db.chatRooms)
              ..where(
                (row) =>
                    row.type.equals(ChatRoomType.group.code) &
                    row.groupId.equals(groupId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.isClosed),
                (row) => OrderingTerm.desc(row.createdAt),
                (row) => OrderingTerm.desc(row.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (existing?.isClosed == true) return existing!;

    late final String roomId;
    if (existing == null) {
      roomId = StableId.chatGroupRoom(groupId);
      final subject = await (db.select(
        db.subjects,
      )..where((row) => row.id.equals(group.subjectId))).getSingleOrNull();
      final now = writer.now();
      await writer.save(
        db.chatRooms,
        ChatRoomsCompanion.insert(
          id: roomId,
          createdAt: now,
          updatedAt: now,
          type: ChatRoomType.group.code,
          groupId: Value(groupId),
          title: Value(
            title?.trim().isNotEmpty == true
                ? title!.trim()
                : '${subject?.name ?? 'المجموعة'} · ${group.number}',
          ),
          createdBy: principal.userId,
        ),
        key: {'id': roomId},
      );
    } else {
      roomId = existing.id;
      if (title?.trim().isNotEmpty == true && title!.trim() != existing.title) {
        await writer.patch(
          db.chatRooms,
          key: {'id': roomId},
          values: {'title': title.trim()},
        );
      }
    }

    final expected = <String, String>{};
    final teacher =
        await (db.select(db.userAccounts)
              ..where(
                (row) =>
                    row.role.equals(UserRole.teacher.code) &
                    row.entityId.equals(group.teacherId) &
                    row.deletedAt.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    if (teacher != null) expected[teacher.id] = teacher.role;
    final parentJoinTimes = await _activeParentAccountJoinTimesForGroup(
      groupId,
    );
    final parentIds = parentJoinTimes.keys;
    for (final parentId in parentIds) {
      expected[parentId] = UserRole.parent.code;
    }
    if (principal.canCreateAny) {
      expected[principal.userId] = principal.role.code;
    }

    final current =
        await (db.select(db.chatMembers)..where(
              (row) => row.roomId.equals(roomId) & row.deletedAt.isNull(),
            ))
            .get();
    for (final member in current) {
      if (!expected.containsKey(member.userId) &&
          (member.userRole == UserRole.teacher.code ||
              member.userRole == UserRole.parent.code)) {
        await writer.softDelete(db.chatMembers, key: {'id': member.id});
      }
    }
    for (final member in expected.entries) {
      final previous =
          await (db.select(db.chatMembers)..where(
                (row) => row.id.equals(StableId.chatMember(roomId, member.key)),
              ))
              .getSingleOrNull();
      final joinedAt = member.value == UserRole.parent.code
          ? parentJoinTimes[member.key]
          : null;
      final allowRestore =
          previous?.deletedAt != null &&
          joinedAt != null &&
          joinedAt > previous!.deletedAt!;
      await _ensureMember(
        roomId,
        member.key,
        member.value,
        allowRestore: allowRestore,
      );
    }
    return _room(roomId);
  }

  /// الغرف التي تخص المستخدم، أو كل الغرف لمراقب المحادثات.
  Stream<List<ChatRoomListItem>> watchRooms({int limit = pageSize}) {
    _validateLimit(limit);
    final canViewAll = principal.canViewAll;
    final variables = <Variable<Object>>[];
    late final String visibility;
    if (canViewAll) {
      visibility = '1 = 1';
    } else {
      variables.add(Variable<String>(principal.userId));
      if (principal.role == UserRole.teacher && principal.entityId != null) {
        visibility =
            'mine.user_id = ? AND mine.deleted_at IS NULL AND '
            '(r.type <> ? OR EXISTS (SELECT 1 FROM groups active_group '
            'WHERE active_group.id = r.group_id '
            'AND active_group.deleted_at IS NULL '
            'AND active_group.archived_at IS NULL '
            'AND active_group.teacher_id = ?))';
        variables.add(Variable<String>(ChatRoomType.group.code));
        variables.add(Variable<String>(principal.entityId!));
      } else if (principal.role == UserRole.parent &&
          principal.entityId != null) {
        visibility =
            'mine.user_id = ? AND mine.deleted_at IS NULL AND '
            '(r.type <> ? OR EXISTS (SELECT 1 FROM groups active_group '
            'JOIN group_students active_link '
            'ON active_link.group_id = active_group.id '
            'AND active_link.deleted_at IS NULL AND active_link.left_at IS NULL '
            'JOIN students active_student '
            'ON active_student.id = active_link.student_id '
            'AND active_student.deleted_at IS NULL '
            'WHERE active_group.id = r.group_id '
            'AND active_group.deleted_at IS NULL '
            'AND active_group.archived_at IS NULL '
            'AND active_student.parent_account_id = ?))';
        variables.add(Variable<String>(ChatRoomType.group.code));
        variables.add(Variable<String>(principal.entityId!));
      } else {
        visibility = 'mine.user_id = ? AND mine.deleted_at IS NULL';
      }
    }
    variables.add(Variable<int>(limit));
    final sql =
        'SELECT r.id, r.type, r.group_id, r.title, r.created_by, '
        'r.is_closed, r.last_message_at, mine.last_read_at, mine.muted, '
        '(SELECT m.content FROM chat_messages m WHERE m.room_id = r.id '
        'AND m.deleted_at IS NULL ORDER BY m.created_at DESC, m.id DESC LIMIT 1) '
        'AS latest_message, '
        '(SELECT m.sender_id FROM chat_messages m WHERE m.room_id = r.id '
        'AND m.deleted_at IS NULL ORDER BY m.created_at DESC, m.id DESC LIMIT 1) '
        'AS latest_sender_id, '
        'CASE WHEN mine.user_id IS NULL THEN 0 ELSE COALESCE('
        '(SELECT COUNT(*) FROM chat_messages unread '
        'WHERE unread.room_id = r.id AND unread.deleted_at IS NULL '
        'AND unread.sender_id <> mine.user_id '
        'AND unread.created_at > COALESCE(mine.last_read_at, 0)), 0) END '
        'AS unread_count '
        'FROM chat_rooms r LEFT JOIN chat_members mine ON mine.room_id = r.id '
        'AND mine.user_id = ? AND mine.deleted_at IS NULL '
        'WHERE r.deleted_at IS NULL AND $visibility '
        'ORDER BY COALESCE(r.last_message_at, r.created_at) DESC, r.id DESC LIMIT ?';
    final queryVariables = <Variable<Object>>[
      Variable<String>(principal.userId),
      ...variables,
    ];
    return db
        .customSelect(
          sql,
          variables: queryVariables,
          readsFrom: {
            db.chatRooms,
            db.chatMembers,
            db.chatMessages,
            db.groups,
            db.groupStudents,
            db.students,
          },
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              ChatRoomListItem(
                id: row.read<String>('id'),
                type: ChatRoomType.fromCode(row.read<String>('type')),
                groupId: row.read<String?>('group_id'),
                title: row.read<String>('title'),
                createdBy: row.read<String>('created_by'),
                isClosed: row.read<bool>('is_closed'),
                lastMessageAt: row.read<int?>('last_message_at'),
                latestMessage: row.read<String?>('latest_message'),
                latestSenderId: row.read<String?>('latest_sender_id'),
                unreadCount: row.read<int>('unread_count'),
                muted: row.read<bool?>('muted') ?? false,
              ),
          ],
        );
  }

  /// بيانات غرفة واحدة، مع إعادة التحقق من العضوية عند تغيّر المجموعة.
  Stream<ChatRoomRow?> watchRoom(String roomId) async* {
    await _requireCanRead(roomId);
    final query = db.customSelect(
      'SELECT * FROM chat_rooms WHERE id = ? AND deleted_at IS NULL',
      variables: [Variable<String>(roomId)],
      readsFrom: {
        db.chatRooms,
        db.chatMembers,
        db.groups,
        db.groupStudents,
        db.students,
      },
    );
    yield* query.watch().asyncMap((rows) async {
      await _requireCanRead(roomId);
      return rows.isEmpty ? null : db.chatRooms.map(rows.first.data);
    });
  }

  /// عضوية المستخدم الحالي في غرفة، لتحديث حالة الكتم مباشرةً.
  Stream<ChatMemberRow?> watchMyMembership(String roomId) async* {
    await _requireCanRead(roomId);
    final query = db.customSelect(
      'SELECT * FROM chat_members WHERE room_id = ? AND user_id = ? '
      'AND deleted_at IS NULL',
      variables: [Variable<String>(roomId), Variable<String>(principal.userId)],
      readsFrom: {
        db.chatMembers,
        db.chatRooms,
        db.groups,
        db.groupStudents,
        db.students,
      },
    );
    yield* query.watch().asyncMap((rows) async {
      await _requireCanRead(roomId);
      return rows.isEmpty ? null : db.chatMembers.map(rows.first.data);
    });
  }

  /// آخر [limit] رسائل الحجرة لحظياً، بترتيب العرض من الأقدم للأحدث.
  Stream<List<ChatMessageRow>> watchLatestMessages(
    String roomId, {
    int limit = pageSize,
  }) async* {
    _validateLimit(limit);
    await _requireCanRead(roomId);
    final query = db.customSelect(
      'SELECT * FROM chat_messages WHERE room_id = ? AND deleted_at IS NULL '
      'ORDER BY created_at DESC, id DESC LIMIT ?',
      variables: [Variable<String>(roomId), Variable<int>(limit)],
      readsFrom: {
        db.chatMessages,
        db.chatRooms,
        db.groups,
        db.groupStudents,
        db.students,
      },
    );
    yield* query.watch().asyncMap((rows) async {
      await _requireCanRead(roomId);
      return rows
          .map((row) => db.chatMessages.map(row.data))
          .toList(growable: false)
          .reversed
          .toList(growable: false);
    });
  }

  /// صفحة حتى 50 رسالة. يعاد أقدم مؤشر للطلب التالي.
  Future<ChatMessagePage> loadMessages(
    String roomId, {
    ChatMessageCursor? before,
    int limit = pageSize,
  }) async {
    _validateLimit(limit);
    await _requireCanRead(roomId);
    final query = db.select(db.chatMessages)
      ..where((row) {
        final base = row.roomId.equals(roomId) & row.deletedAt.isNull();
        if (before == null) return base;
        return base &
            (row.createdAt.isSmallerThanValue(before.createdAt) |
                (row.createdAt.equals(before.createdAt) &
                    row.id.isSmallerThanValue(before.id)));
      })
      ..orderBy([
        (row) => OrderingTerm.desc(row.createdAt),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(limit + 1);
    final rows = await query.get();
    final hasMore = rows.length > limit;
    final messages = rows.take(limit).toList().reversed.toList(growable: false);
    return ChatMessagePage(
      messages: messages,
      hasMore: hasMore,
      nextCursor: messages.isEmpty
          ? null
          : ChatMessageCursor(
              createdAt: messages.first.createdAt,
              id: messages.first.id,
            ),
    );
  }

  /// يكتب محلياً فوراً عبر SyncWriter؛ تظهر الرسالة قبل اكتمال رفع outbox.
  Future<ChatMessageRow> sendText(String roomId, String content) =>
      sendMessage(roomId, content: content);

  /// يرسل نصاً أو مرفقاً مُحمّلاً محلياً، ثم يحدّث ترتيب الغرفة.
  Future<ChatMessageRow> sendMessage(
    String roomId, {
    String content = '',
    String? attachmentUrl,
    String? attachmentName,
    ChatAttachmentType? attachmentType,
    String? attachmentLocalPath,
    int attachmentSizeBytes = 0,
  }) async {
    _requireWriterActor();
    final text = content.trim();
    final hasAttachment =
        attachmentUrl != null ||
        attachmentName != null ||
        attachmentLocalPath != null;
    if (text.isEmpty && !hasAttachment) {
      throw ArgumentError('أدخل نصاً أو أرفق ملفاً');
    }
    if (text.length > 10000) {
      throw ArgumentError.value(
        text.length,
        'content',
        'الرسالة أطول من الحد المسموح',
      );
    }
    if (hasAttachment) {
      if (attachmentType == null ||
          attachmentSizeBytes < 0 ||
          attachmentSizeBytes > maximumAttachmentBytes) {
        throw ArgumentError('المرفق غير صالح أو يتجاوز 10MB');
      }
      if (attachmentName?.trim().isEmpty ?? true) {
        throw ArgumentError('اسم المرفق مطلوب');
      }
    }
    await _requireCanSend(roomId);
    final room = await _room(roomId);
    final now = writer.now();
    final id = writer.newId();
    await db.transaction(() async {
      await writer.save(
        db.chatMessages,
        ChatMessagesCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          roomId: roomId,
          senderId: principal.userId,
          senderRole: principal.role.code,
          content: Value(text),
          attachmentUrl: Value(attachmentUrl),
          attachmentName: Value(attachmentName?.trim()),
          attachmentType: Value(attachmentType?.code),
          attachmentLocalPath: Value(attachmentLocalPath),
        ),
        key: {'id': id},
      );
      if (attachmentLocalPath != null && attachmentUrl == null) {
        final extension = attachmentName!.split('.').last.toLowerCase();
        final safeExtension = RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension)
            ? extension
            : 'bin';
        await UploadQueueWriter(db, writer).enqueue(
          kind: 'chat_attachment',
          bucket: 'files',
          localPath: attachmentLocalPath,
          remotePath: 'chat/$roomId/$id.$safeExtension',
          dedupeKey: 'chat_attachment:$id',
          targetTable: 'chat_messages',
          targetRowId: id,
          targetColumn: 'attachment_url',
        );
      }
      await writer.patch(
        db.chatRooms,
        key: {'id': room.id},
        values: {'last_message_at': now},
      );
    });
    return (db.select(
      db.chatMessages,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  /// يحدّث آخر قراءة للمستخدم الحالي.
  Future<void> markRead(String roomId) async {
    _requireWriterActor();
    await _requireCanRead(roomId);
    final member = await _requireMembership(roomId);
    await writer.patch(
      db.chatMembers,
      key: {'id': member.id},
      values: {'last_read_at': writer.now()},
    );
  }

  /// يكتُم أو يعيد تنبيهات الغرفة لهذا المستخدم فقط.
  Future<void> setMuted(String roomId, {required bool muted}) async {
    _requireWriterActor();
    await _requireCanRead(roomId);
    final member = await _requireMembership(roomId);
    if (member.muted == muted) return;
    await writer.patch(
      db.chatMembers,
      key: {'id': member.id},
      values: {'muted': muted},
    );
  }

  /// يغلق الغرفة؛ صاحب المدرسة أو من فعّل له المدير تعديل المحادثات.
  Future<bool> closeRoom(String roomId) async {
    _requireWriterActor();
    _requireManager();
    final room = await _room(roomId);
    if (room.isClosed) return false;
    return writer.patch(
      db.chatRooms,
      key: {'id': roomId},
      values: {'is_closed': true},
    );
  }

  /// يحذف رسالة ناعماً؛ يحق للمرسل حذف رسالته أو للمراقب حذف أي رسالة.
  Future<bool> deleteMessage(String messageId) async {
    _requireWriterActor();
    final message = await (db.select(
      db.chatMessages,
    )..where((row) => row.id.equals(messageId))).getSingleOrNull();
    if (message == null || message.deletedAt != null) return false;
    if (message.senderId != principal.userId && !principal.canDeleteAny) {
      throw const ChatAccessException('حذف رسالة مستخدم آخر غير مسموح');
    }
    if (!principal.canDeleteAny) await _requireCanRead(message.roomId);
    return writer.softDelete(db.chatMessages, key: {'id': messageId});
  }

  /// يزيل عضواً من الغرفة، ولا يملكها إلا المالك أو المراقب.
  Future<bool> removeMember(String roomId, String userId) async {
    _requireWriterActor();
    _requireManager();
    if (userId == principal.userId && principal.role != UserRole.owner) {
      throw const ChatAccessException('لا يمكن للمراقب إزالة نفسه من الغرفة');
    }
    final member =
        await (db.select(db.chatMembers)..where(
              (row) =>
                  row.roomId.equals(roomId) &
                  row.userId.equals(userId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (member == null) return false;
    return writer.softDelete(db.chatMembers, key: {'id': member.id});
  }

  Future<ChatRoomRow> _room(String id) async {
    final room =
        await (db.select(db.chatRooms)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (room == null) throw const ChatAccessException('الغرفة غير موجودة');
    return room;
  }

  Future<UserAccountRow> _account(String id) async {
    final account =
        await (db.select(db.userAccounts)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (account == null) {
      throw const ChatAccessException('الحساب غير موجود أو معطّل');
    }
    return account;
  }

  Future<bool> _canMessage(UserAccountRow target) async {
    if (principal.canCreateAny) return true;
    if (principal.role == UserRole.teacher &&
        principal.entityId != null &&
        target.role == UserRole.parent.code &&
        target.entityId != null) {
      return _shareActiveGroup(principal.entityId!, target.entityId!);
    }
    if (principal.role == UserRole.parent &&
        principal.entityId != null &&
        target.role == UserRole.teacher.code &&
        target.entityId != null) {
      return _shareActiveGroup(target.entityId!, principal.entityId!);
    }
    return false;
  }

  Future<bool> _shareActiveGroup(
    String teacherId,
    String parentAccountId,
  ) async {
    final row = await db
        .customSelect(
          'SELECT 1 AS matched FROM groups g '
          'JOIN group_students gs ON gs.group_id = g.id '
          'AND gs.deleted_at IS NULL AND gs.left_at IS NULL '
          'JOIN students s ON s.id = gs.student_id AND s.deleted_at IS NULL '
          'WHERE g.teacher_id = ? AND s.parent_account_id = ? '
          'AND g.deleted_at IS NULL AND g.archived_at IS NULL LIMIT 1',
          variables: [
            Variable<String>(teacherId),
            Variable<String>(parentAccountId),
          ],
          readsFrom: {db.groups, db.groupStudents, db.students},
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<Map<String, int>> _activeParentAccountJoinTimesForGroup(
    String groupId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT ua.id AS account_id, MAX(gs.joined_at) AS joined_at '
          'FROM group_students gs JOIN students s ON s.id = gs.student_id '
          'JOIN user_accounts ua ON ua.entity_id = s.parent_account_id '
          'AND ua.role = ? AND ua.deleted_at IS NULL '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL AND gs.left_at IS NULL '
          'AND s.deleted_at IS NULL AND s.parent_account_id IS NOT NULL '
          'GROUP BY ua.id',
          variables: [
            Variable<String>(UserRole.parent.code),
            Variable<String>(groupId),
          ],
          readsFrom: {
            db.groupStudents,
            db.students,
            db.userAccounts,
            db.groups,
          },
        )
        .get();
    final joinTimes = <String, int>{};
    for (final row in rows) {
      final id = row.read<String?>('account_id');
      final joinedAt = row.read<int?>('joined_at');
      if (id != null && joinedAt != null) joinTimes[id] = joinedAt;
    }
    return joinTimes;
  }

  Future<Set<String>> _activeParentAccountsForGroup(String groupId) async =>
      (await _activeParentAccountJoinTimesForGroup(groupId)).keys.toSet();

  Future<void> _ensureMember(
    String roomId,
    String userId,
    String role, {
    bool allowRestore = false,
  }) async {
    final id = StableId.chatMember(roomId, userId);
    final existing = await (db.select(
      db.chatMembers,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing != null && (existing.deletedAt == null || !allowRestore)) {
      return;
    }
    final now = writer.now();
    await writer.save(
      db.chatMembers,
      ChatMembersCompanion.insert(
        id: id,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        roomId: roomId,
        userId: userId,
        userRole: role,
        lastReadAt: Value(existing?.lastReadAt ?? 0),
        muted: Value(existing?.muted ?? false),
        deletedAt: const Value(null),
      ),
      key: {'id': id},
    );
  }

  Future<ChatMemberRow> _requireMembership(String roomId) async {
    final member =
        await (db.select(db.chatMembers)..where(
              (row) =>
                  row.roomId.equals(roomId) &
                  row.userId.equals(principal.userId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (member == null) {
      throw const ChatAccessException('أنت لست عضواً في هذه الغرفة');
    }
    return member;
  }

  Future<void> _requireCanRead(String roomId) async {
    final room = await _room(roomId);
    if (principal.canViewAll) return;
    await _requireMembership(roomId);
    if (room.type == ChatRoomType.group.code &&
        (principal.role == UserRole.teacher ||
            principal.role == UserRole.parent) &&
        !await _isActiveGroupParticipant(room)) {
      throw const ChatAccessException('انتهت عضويتك في هذه المجموعة');
    }
  }

  Future<void> _requireCanSend(String roomId) async {
    final room = await _room(roomId);
    if (room.isClosed) throw const ChatAccessException('الغرفة مغلقة');
    if (_canSendAsModerator) return;
    await _requireMembership(roomId);
    if (room.type == ChatRoomType.group.code &&
        (principal.role == UserRole.teacher ||
            principal.role == UserRole.parent) &&
        !await _isActiveGroupParticipant(room)) {
      throw const ChatAccessException('انتهت عضويتك في هذه المجموعة');
    }
    if (room.type == ChatRoomType.private.code &&
        (principal.role == UserRole.teacher ||
            principal.role == UserRole.parent)) {
      final others =
          await (db.select(db.chatMembers)..where(
                (row) =>
                    row.roomId.equals(roomId) &
                    row.deletedAt.isNull() &
                    row.userId.isNotValue(principal.userId),
              ))
              .get();
      if (others.isEmpty) {
        throw const ChatAccessException('الغرفة الخاصة بلا طرف آخر');
      }
      final target = await _account(others.first.userId);
      if (!await _canMessage(target)) {
        throw const ChatAccessException('لم تعد هناك مجموعة نشطة مشتركة');
      }
    }
  }

  Future<bool> _isActiveGroupParticipant(ChatRoomRow room) async {
    final groupId = room.groupId;
    if (groupId == null) return false;
    if (principal.role == UserRole.teacher) {
      final group =
          await (db.select(db.groups)..where(
                (row) =>
                    row.id.equals(groupId) &
                    row.deletedAt.isNull() &
                    row.archivedAt.isNull(),
              ))
              .getSingleOrNull();
      return group?.teacherId == principal.entityId;
    }
    if (principal.role == UserRole.parent && principal.entityId != null) {
      final group =
          await (db.select(db.groups)..where(
                (row) =>
                    row.id.equals(groupId) &
                    row.deletedAt.isNull() &
                    row.archivedAt.isNull(),
              ))
              .getSingleOrNull();
      if (group == null) return false;
      return (await _activeParentAccountsForGroup(groupId))
          .contains(principal.userId);
    }
    return true;
  }

  void _requireManager() {
    if (!principal.canManage) {
      throw const ChatAccessException(
        'تحتاج هذه العملية صلاحية تعديل المحادثات',
      );
    }
  }

  void _requireWriterActor() {
    if (writer.actor().userId != principal.userId) {
      throw const ChatAccessException(
        'الجلسة الحالية لا تطابق كاتب قاعدة البيانات',
      );
    }
  }

  void _validateLimit(int limit) {
    if (limit < 1 || limit > pageSize) {
      throw ArgumentError.value(
        limit,
        'limit',
        'الدفعة يجب أن تكون بين 1 و$pageSize',
      );
    }
  }
}
