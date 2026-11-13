import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_chat/school_chat.dart';
import 'package:school_core/school_core.dart';

void main() {
  late _Harness h;

  setUp(() async {
    h = _Harness();
    await h.seed();
  });
  tearDown(() => h.close());

  test('stable room IDs derive from their natural keys', () async {
    final privateRoom = await h.teacher.createPrivateRoom('u-parent');
    expect(privateRoom.id, StableId.chatPrivateRoom('u-teacher', 'u-parent'));

    final groupRoom = await h.teacher.createGroupRoom('g1');
    expect(groupRoom.id, StableId.chatGroupRoom('g1'));
  });

  group('private conversation policy', () {
    test(
      'teachers and parents see only contacts in an active shared group',
      () async {
        final teacherContacts = await h.teacher.privateContacts();
        expect(teacherContacts.map((contact) => contact.accountId), [
          'u-parent',
        ]);

        final parent = h.service('u-parent', UserRole.parent, entityId: 'p1');
        final parentContacts = await parent.privateContacts();
        expect(parentContacts.map((contact) => contact.accountId), [
          'u-teacher',
        ]);

        final unrelated = h.service(
          'u-other-parent',
          UserRole.parent,
          entityId: 'p2',
        );
        expect(await unrelated.privateContacts(), isEmpty);
      },
    );

    test(
      'creates one private room per pair and rejects unrelated accounts',
      () async {
        final room = await h.teacher.createPrivateRoom('u-parent');
        final again = await h.teacher.createPrivateRoom('u-parent');
        final members = await h.members(room.id);

        expect(room.type, ChatRoomType.private.code);
        expect(again.id, room.id);
        expect(members.map((member) => member.userId).toSet(), {
          'u-teacher',
          'u-parent',
        });
        await expectLater(
          h.teacher.createPrivateRoom('u-other-parent'),
          throwsA(isA<ChatAccessException>()),
        );
      },
    );
  });

  group('group rooms', () {
    test(
      'deduplicates parent accounts and refreshes current group membership',
      () async {
        final room = await h.teacher.createGroupRoom('g1');
        expect(
          (await h.members(room.id)).map((member) => member.userId).toSet(),
          {'u-teacher', 'u-parent'},
        );

        await h.addToGroup('s3');
        final refreshed = await h.teacher.createGroupRoom('g1');
        expect(refreshed.id, room.id);
        expect(
          (await h.members(room.id)).map((member) => member.userId).toSet(),
          {'u-teacher', 'u-parent', 'u-other-parent'},
        );

        final oldLinks = await (h.db.select(
          h.db.groupStudents,
        )..where((row) => row.studentId.isIn(['s1', 's2']))).get();
        for (final link in oldLinks) {
          await h.writer.patch(
            h.db.groupStudents,
            key: {'id': link.id},
            values: {'left_at': 1001},
          );
        }
        await h.teacher.createGroupRoom('g1');
        expect(
          (await h.members(room.id)).map((member) => member.userId).toSet(),
          {'u-teacher', 'u-other-parent'},
        );
      },
    );

    test(
      'only the group teacher or a chat manager may create its room',
      () async {
        final otherTeacher = h.service(
          'u-other-teacher',
          UserRole.teacher,
          entityId: 't2',
        );
        await expectLater(
          otherTeacher.createGroupRoom('g1'),
          throwsA(isA<ChatAccessException>()),
        );

        final manager = h.service(
          'u-worker',
          UserRole.worker,
          permissions: WorkerPermissions.none.withAction(
            PermissionModule.chat,
            PermissionAction.add,
            allowed: true,
          ),
        );
        final room = await manager.createGroupRoom('g1');
        expect(room.groupId, 'g1');
      },
    );

    test('removed parents lose the room preview and message access', () async {
      final room = await h.teacher.createGroupRoom('g1');
      await h.teacher.sendText(room.id, 'رسالة للمجموعة');
      final parent = h.service('u-parent', UserRole.parent, entityId: 'p1');
      final parentMessage = await parent.sendText(room.id, 'ردّ الولي');
      expect(
        (await parent.watchRooms().first).single.latestMessage,
        'ردّ الولي',
      );

      final links = await (h.db.select(
        h.db.groupStudents,
      )..where((row) => row.studentId.isIn(['s1', 's2']))).get();
      for (final link in links) {
        await h.writer.patch(
          h.db.groupStudents,
          key: {'id': link.id},
          values: {'left_at': 1001},
        );
      }

      expect(await parent.watchRooms().first, isEmpty);
      await expectLater(
        parent.loadMessages(room.id),
        throwsA(isA<ChatAccessException>()),
      );
      await expectLater(
        parent.sendText(room.id, 'بعد المغادرة'),
        throwsA(isA<ChatAccessException>()),
      );
      await expectLater(
        parent.deleteMessage(parentMessage.id),
        throwsA(isA<ChatAccessException>()),
      );
      await expectLater(
        parent.markRead(room.id),
        throwsA(isA<ChatAccessException>()),
      );
      await expectLater(
        parent.setMuted(room.id, muted: true),
        throwsA(isA<ChatAccessException>()),
      );
    });

    test('open room streams stop when a parent leaves the group', () async {
      final room = await h.teacher.createGroupRoom('g1');
      await h.teacher.sendText(room.id, 'رسالة قبل المغادرة');
      final parent = h.service('u-parent', UserRole.parent, entityId: 'p1');
      final roomStream = StreamIterator(parent.watchRoom(room.id));
      final messageStream = StreamIterator(parent.watchLatestMessages(room.id));

      expect(await roomStream.moveNext(), isTrue);
      expect(roomStream.current?.id, room.id);
      expect(await messageStream.moveNext(), isTrue);
      expect(messageStream.current.single.content, 'رسالة قبل المغادرة');

      final links = await (h.db.select(
        h.db.groupStudents,
      )..where((row) => row.studentId.isIn(['s1', 's2']))).get();
      for (final link in links) {
        await h.owner.writer.patch(
          h.db.groupStudents,
          key: {'id': link.id},
          values: {'left_at': 1001},
        );
      }

      await expectLater(
        roomStream.moveNext(),
        throwsA(isA<ChatAccessException>()),
      );
      await expectLater(
        messageStream.moveNext(),
        throwsA(isA<ChatAccessException>()),
      );
      await roomStream.cancel();
      await messageStream.cancel();
    });

    test(
      'archiving a group removes it from private participant access',
      () async {
        final room = await h.teacher.createGroupRoom('g1');
        await h.teacher.sendText(room.id, 'أرشيف المجموعة');
        await h.writer.patch(
          h.db.groups,
          key: {'id': 'g1'},
          values: {'archived_at': 1001},
        );
        final parent = h.service('u-parent', UserRole.parent, entityId: 'p1');

        expect(await parent.watchRooms().first, isEmpty);
        await expectLater(
          parent.loadMessages(room.id),
          throwsA(isA<ChatAccessException>()),
        );
      },
    );

    test('moderator removal survives a group membership refresh', () async {
      final room = await h.teacher.createGroupRoom('g1');
      await h.owner.removeMember(room.id, 'u-parent');

      final teacher = h.service('u-teacher', UserRole.teacher, entityId: 't1');
      await teacher.createGroupRoom('g1');

      expect((await h.members(room.id)).map((member) => member.userId), [
        'u-teacher',
      ]);
    });

    test('a parent who rejoins later is restored to the group room', () async {
      final room = await h.teacher.createGroupRoom('g1');
      final links = await (h.db.select(
        h.db.groupStudents,
      )..where((row) => row.studentId.isIn(['s1', 's2']))).get();
      for (final link in links) {
        await h.writer.patch(
          h.db.groupStudents,
          key: {'id': link.id},
          values: {'left_at': 1001},
        );
      }
      await h.teacher.createGroupRoom('g1');
      final removed =
          await (h.db.select(h.db.chatMembers)..where(
                (row) =>
                    row.id.equals(StableId.chatMember(room.id, 'u-parent')),
              ))
              .getSingle();

      final link = links.firstWhere((row) => row.studentId == 's1');
      final rejoinedAt = removed.deletedAt! + 1;
      await h.writer.save(
        h.db.groupStudents,
        link
            .toCompanion(false)
            .copyWith(
              updatedAt: Value(rejoinedAt),
              joinedAt: Value(rejoinedAt),
              leftAt: const Value(null),
              deletedAt: const Value(null),
            ),
        key: {'id': link.id},
      );
      await h.teacher.createGroupRoom('g1');

      expect(
        (await h.members(room.id)).map((member) => member.userId).toSet(),
        {'u-teacher', 'u-parent'},
      );
    });

    test(
      'a closed group room is never reopened by membership refresh',
      () async {
        final room = await h.teacher.createGroupRoom('g1');
        await h.owner.closeRoom(room.id);
        final teacher = h.service(
          'u-teacher',
          UserRole.teacher,
          entityId: 't1',
        );

        final closedRoom = await teacher.createGroupRoom('g1');

        expect(closedRoom.id, room.id);
        expect(closedRoom.isClosed, isTrue);
      },
    );
  });

  group('messages and local sending', () {
    test(
      'saves optimistically and paginates at 50 in chronological order',
      () async {
        final room = await h.teacher.createPrivateRoom('u-parent');
        for (var i = 1; i <= 53; i++) {
          await h.teacher.sendText(room.id, 'رسالة $i');
        }

        final latest = await h.teacher.loadMessages(room.id);
        expect(latest.messages, hasLength(50));
        expect(latest.messages.first.content, 'رسالة 4');
        expect(latest.messages.last.content, 'رسالة 53');
        expect(latest.hasMore, isTrue);

        final older = await h.teacher.loadMessages(
          room.id,
          before: latest.nextCursor,
        );
        expect(older.messages.map((row) => row.content), [
          'رسالة 1',
          'رسالة 2',
          'رسالة 3',
        ]);
        expect(older.hasMore, isFalse);

        final streamed = await h.teacher.watchLatestMessages(room.id).first;
        expect(streamed, hasLength(50));
        expect(streamed.last.content, 'رسالة 53');
        final outbox = await (h.db.select(
          h.db.outbox,
        )..where((row) => row.targetTable.equals('chat_messages'))).get();
        expect(outbox, hasLength(53));
        expect((await h.room(room.id)).lastMessageAt, greaterThan(1000));
      },
    );

    test('rejects empty messages, oversized attachments, and sends to a closed room', () async {
      final room = await h.teacher.createPrivateRoom('u-parent');
      await expectLater(
        h.teacher.sendText(room.id, '   '),
        throwsArgumentError,
      );
      await expectLater(
        h.teacher.sendMessage(
          room.id,
          attachmentName: 'large.pdf',
          attachmentType: ChatAttachmentType.file,
          attachmentLocalPath: 'large.pdf',
          attachmentSizeBytes: ChatService.maximumAttachmentBytes + 1,
        ),
        throwsArgumentError,
      );

      final manager = h.owner;
      await manager.closeRoom(room.id);
      final teacher = h.service('u-teacher', UserRole.teacher, entityId: 't1');
      final existingRoom = await teacher.createPrivateRoom('u-parent');
      expect(existingRoom.id, room.id);
      expect(existingRoom.isClosed, isTrue);
      await expectLater(
        teacher.sendText(room.id, 'بعد الإغلاق'),
        throwsA(isA<ChatAccessException>()),
      );
    });

    test('supports local files within 10MB', () async {
      final room = await h.teacher.createPrivateRoom('u-parent');
      final message = await h.teacher.sendMessage(
        room.id,
        attachmentName: 'worksheet.pdf',
        attachmentType: ChatAttachmentType.file,
        attachmentLocalPath: 'local/worksheet.pdf',
        attachmentSizeBytes: 10 * 1024 * 1024,
      );
      expect(message.content, isEmpty);
      expect(message.attachmentName, 'worksheet.pdf');
      expect(message.attachmentLocalPath, 'local/worksheet.pdf');
      final uploads = await h.db.select(h.db.uploadQueue).get();
      expect(uploads, hasLength(1));
      expect(uploads.single.bucket, 'files');
      expect(uploads.single.targetTable, 'chat_messages');
      expect(uploads.single.targetRowId, message.id);
      expect(uploads.single.targetColumn, 'attachment_url');
      expect(uploads.single.remotePath, 'chat/${room.id}/${message.id}.pdf');
    });
  });

  group('read state and moderation', () {
    test(
      'rejects writes through a chat service from a previous session',
      () async {
        final room = await h.teacher.createPrivateRoom('u-parent');
        h.service('u-parent', UserRole.parent, entityId: 'p1');

        await expectLater(
          h.teacher.markRead(room.id),
          throwsA(isA<ChatAccessException>()),
        );
        expect((await h.members(room.id)).first.lastReadAt, 0);
      },
    );

    test('tracks unread count, per-member mute, and read timestamp', () async {
      final room = await h.teacher.createPrivateRoom('u-parent');
      await h.teacher.sendText(room.id, 'رسالة للولي');
      final parent = h.service('u-parent', UserRole.parent, entityId: 'p1');

      var summary = (await parent.watchRooms().first).single;
      expect(summary.unreadCount, 1);
      expect(summary.latestMessage, 'رسالة للولي');
      await parent.setMuted(room.id, muted: true);
      summary = (await parent.watchRooms().first).single;
      expect(summary.muted, isTrue);
      await parent.markRead(room.id);
      summary = (await parent.watchRooms().first).single;
      expect(summary.unreadCount, 0);
    });

    test(
      'moderator can close a room, remove a member, and delete a message',
      () async {
        final room = await h.teacher.createPrivateRoom('u-parent');
        final message = await h.teacher.sendText(room.id, 'رسالة قابلة للحذف');
        final manager = h.owner;
        final members = await manager.roomMembers(room.id);

        expect(
          members.map((member) => (member.userId, member.displayName)),
          unorderedEquals([
            ('u-parent', 'ولي سمير'),
            ('u-teacher', 'الأستاذ كمال'),
          ]),
        );

        final adminReply = await manager.sendText(room.id, 'رسالة الإدارة');
        expect(adminReply.senderRole, UserRole.owner.code);
        expect(await manager.deleteMessage(message.id), isTrue);
        expect(await manager.removeMember(room.id, 'u-parent'), isTrue);
        expect(
          (await manager.roomMembers(room.id)).map((member) => member.userId),
          ['u-teacher'],
        );
        expect(await manager.closeRoom(room.id), isTrue);
        expect(await manager.closeRoom(room.id), isFalse);
        expect(
          (await manager.loadMessages(room.id)).messages
              .map((row) => row.content),
          ['رسالة الإدارة'],
        );
        expect((await manager.watchRooms().first).single.isClosed, isTrue);
      },
    );

    test(
      'chat edit permission monitors and writes to non-member rooms',
      () async {
        final room = await h.teacher.createPrivateRoom('u-parent');
        final manager = h.service(
          'u-worker',
          UserRole.worker,
          entityId: 'w1',
          permissions: WorkerPermissions.none.withAction(
            PermissionModule.chat,
            PermissionAction.edit,
            allowed: true,
          ),
        );

        final sent = await manager.sendText(room.id, 'متابعة الإدارة');

        expect(sent.senderRole, UserRole.worker.code);
        final roomSummary = (await manager.watchRooms().first).single;
        expect(roomSummary.latestMessage, 'متابعة الإدارة');
        expect(roomSummary.unreadCount, 0);
        expect(
          (await manager.loadMessages(room.id)).messages.single.content,
          'متابعة الإدارة',
        );
      },
    );

    test('non-members cannot read or mutate the room', () async {
      final room = await h.teacher.createPrivateRoom('u-parent');
      final outsider = h.service(
        'u-other-parent',
        UserRole.parent,
        entityId: 'p2',
      );
      await expectLater(
        outsider.loadMessages(room.id),
        throwsA(isA<ChatAccessException>()),
      );
      await expectLater(
        outsider.sendText(room.id, 'تطفل'),
        throwsA(isA<ChatAccessException>()),
      );
    });
  });
}

class _Harness {
  _Harness() : db = AppDatabase(NativeDatabase.memory()) {
    writer = SyncWriter(
      db,
      actor: () => Actor(userId: actorId, userName: actorId),
      clock: () => 1000,
      idGenerator: () => 'chat-${++_ids}',
    );
    teacher = service('u-teacher', UserRole.teacher, entityId: 't1');
  }

  final AppDatabase db;
  late final SyncWriter writer;
  late final ChatService teacher;
  String actorId = 'u-teacher';
  int _ids = 0;

  ChatService get owner => service('u-owner', UserRole.owner);

  ChatService service(
    String id,
    UserRole role, {
    String? entityId,
    WorkerPermissions permissions = WorkerPermissions.none,
  }) {
    actorId = id;
    return ChatService(
      db,
      writer,
      ChatPrincipal(
        userId: id,
        role: role,
        entityId: entityId,
        policy: AccessPolicy(role: role, permissions: permissions),
      ),
    );
  }

  Future<void> seed() async {
    await db.batch((batch) {
      batch.insertAll(db.subjects, [
        SubjectsCompanion.insert(
          id: 'sub1',
          createdAt: 1,
          updatedAt: 1,
          name: 'رياضيات',
        ),
      ]);
      batch.insertAll(db.teachers, [
        _teacher('t1', 'كمال', '0660000001'),
        _teacher('t2', 'ياسين', '0660000002'),
      ]);
      batch.insertAll(db.parents, [
        _parent('p1', 'ولي سمير', '0550000001'),
        _parent('p2', 'ولي أمين', '0550000002'),
      ]);
      batch.insertAll(db.students, [
        _student('s1', 'سمير', 'p1'),
        _student('s2', 'نور', 'p1'),
        _student('s3', 'أمين', 'p2'),
      ]);
      batch.insertAll(db.groups, [
        GroupsCompanion.insert(
          id: 'g1',
          createdAt: 1,
          updatedAt: 1,
          number: 1,
          subjectId: 'sub1',
          teacherId: 't1',
        ),
        GroupsCompanion.insert(
          id: 'g2',
          createdAt: 1,
          updatedAt: 1,
          number: 2,
          subjectId: 'sub1',
          teacherId: 't2',
        ),
      ]);
      batch.insertAll(db.groupStudents, [
        _groupStudent('s1'),
        _groupStudent('s2'),
      ]);
      batch.insertAll(db.userAccounts, [
        _account(
          'u-teacher',
          UserRole.teacher,
          entityId: 't1',
          name: 'الأستاذ كمال',
        ),
        _account('u-parent', UserRole.parent, entityId: 'p1', name: 'ولي سمير'),
        _account(
          'u-other-teacher',
          UserRole.teacher,
          entityId: 't2',
          name: 'الأستاذ ياسين',
        ),
        _account(
          'u-other-parent',
          UserRole.parent,
          entityId: 'p2',
          name: 'ولي أمين',
        ),
        _account('u-owner', UserRole.owner, name: 'المدير'),
        _account('u-worker', UserRole.worker, entityId: 'w1', name: 'عامل'),
      ]);
    });
  }

  Future<void> addToGroup(String studentId, {int joinedAt = 1}) => db
      .into(db.groupStudents)
      .insert(_groupStudent(studentId, joinedAt: joinedAt));

  Future<List<ChatMemberRow>> members(String roomId) => (db.select(
    db.chatMembers,
  )..where((row) => row.roomId.equals(roomId) & row.deletedAt.isNull())).get();

  Future<ChatRoomRow> room(String id) =>
      (db.select(db.chatRooms)..where((row) => row.id.equals(id))).getSingle();

  Future<void> close() => db.close();
}

TeachersCompanion _teacher(String id, String name, String phone) =>
    TeachersCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      name: name,
      phone: phone,
      email: '$id@school.local',
      qrCode: 'T-$id',
    );

ParentsCompanion _parent(String id, String name, String phone) =>
    ParentsCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      phone: phone,
      email: '$id@school.local',
      name: Value(name),
    );

StudentsCompanion _student(String id, String name, String parentId) =>
    StudentsCompanion.insert(
      id: id,
      createdAt: 1,
      updatedAt: 1,
      firstName: name,
      lastName: 'بن علي',
      parentPhone: '0550000001',
      parentAccountId: Value(parentId),
      qrCode: 'S-$id',
    );

GroupStudentsCompanion _groupStudent(String studentId, {int joinedAt = 1}) =>
    GroupStudentsCompanion.insert(
      id: StableId.groupStudent('g1', studentId),
      createdAt: 1,
      updatedAt: 1,
      groupId: 'g1',
      studentId: studentId,
      joinedAt: joinedAt,
      monthlyPrice: 2000,
    );

UserAccountsCompanion _account(
  String id,
  UserRole role, {
  String? entityId,
  required String name,
}) => UserAccountsCompanion.insert(
  id: id,
  createdAt: 1,
  updatedAt: 1,
  email: '$id@school.local',
  role: role.code,
  entityId: Value(entityId),
  displayName: Value(name),
  mustChangePassword: const Value(false),
);
