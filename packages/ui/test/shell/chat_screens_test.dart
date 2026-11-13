import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_chat/school_chat.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

void main() {
  testWidgets('inbox shows latest text, unread count, and mute state', (
    tester,
  ) async {
    const room = ChatRoomListItem(
      id: 'private-room',
      type: ChatRoomType.private,
      groupId: null,
      title: 'وليّ سمير',
      createdBy: 'teacher',
      isClosed: false,
      lastMessageAt: 10,
      latestMessage: 'تذكير بموعد الحصة',
      latestSenderId: 'parent',
      unreadCount: 3,
      muted: true,
    );
    await tester.pumpWidget(
      ClayApp(
        app: AppIdentity.teacher,
        home: ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => Stream.value(null)),
            chatRoomsProvider(ChatService.pageSize)
                .overrideWith((ref) => Stream.value([room])),
          ],
          child: const ChatInboxScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('وليّ سمير'), findsOneWidget);
    expect(find.text('تذكير بموعد الحصة'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip('محادثة جديدة'), findsNothing);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
  });

  testWidgets('chat view permission can read but cannot send', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'worker', userName: 'عامل'),
      clock: () => 100,
      idGenerator: () => 'worker-chat-id',
    );
    await db
        .into(db.chatRooms)
        .insert(
          ChatRoomsCompanion.insert(
            id: 'private-room',
            createdAt: 1,
            updatedAt: 1,
            type: ChatRoomType.private.code,
            title: const Value('محادثة للمراقبة'),
            createdBy: 'teacher',
          ),
        );
    final service = ChatService(
      db,
      writer,
      const ChatPrincipal(
        userId: 'worker',
        role: UserRole.worker,
        policy: AccessPolicy(
          role: UserRole.worker,
          permissions: WorkerPermissions({
            PermissionModule.chat: {PermissionAction.view},
          }),
        ),
      ),
    );
    final session = AuthSession(
      const AccountRecord(
        id: 'worker',
        email: 'worker@example.test',
        role: UserRole.worker,
        displayName: 'عامل',
        mustChangePassword: false,
        permissions: WorkerPermissions({
          PermissionModule.chat: {PermissionAction.view},
        }),
      ),
    );

    await tester.pumpWidget(
      ClayApp(
        app: AppIdentity.admin,
        home: ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => Stream.value(session)),
            chatServiceProvider.overrideWith((ref) => service),
          ],
          child: const ChatRoomScreen(roomId: 'private-room'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    final sendButton = find.ancestor(
      of: find.byIcon(Icons.send_rounded),
      matching: find.byType(IconButton),
    );
    final attachmentButton = find.ancestor(
      of: find.byIcon(Icons.attach_file_rounded),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
    expect(tester.widget<IconButton>(attachmentButton).onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('room renders messages and toggles the current member mute', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'parent', userName: 'ولي سمير'),
      clock: () => 100,
      idGenerator: () => 'ui-chat-id',
    );
    await db
        .into(db.chatRooms)
        .insert(
          ChatRoomsCompanion.insert(
            id: 'private-room',
            createdAt: 1,
            updatedAt: 1,
            type: ChatRoomType.private.code,
            title: const Value('الأستاذ كمال'),
            createdBy: 'parent',
          ),
        );
    await db
        .into(db.chatMembers)
        .insert(
          ChatMembersCompanion.insert(
            id: 'member-parent',
            createdAt: 1,
            updatedAt: 1,
            roomId: 'private-room',
            userId: 'parent',
            userRole: UserRole.parent.code,
          ),
        );
    final service = ChatService(
      db,
      writer,
      const ChatPrincipal(
        userId: 'parent',
        role: UserRole.parent,
        entityId: 'p1',
        policy: AccessPolicy(role: UserRole.parent),
      ),
    );
    final session = AuthSession(
      const AccountRecord(
        id: 'parent',
        email: 'parent@example.test',
        role: UserRole.parent,
        entityId: 'p1',
        displayName: 'ولي سمير',
        mustChangePassword: false,
      ),
    );
    final room = ChatRoomRow(
      id: 'private-room',
      createdAt: 1,
      updatedAt: 1,
      type: ChatRoomType.private.code,
      title: 'الأستاذ كمال',
      createdBy: 'parent',
      isClosed: false,
    );
    const messagesKey = (roomId: 'private-room', limit: ChatService.pageSize);
    final message = ChatMessageRow(
      id: 'message-1',
      createdAt: 100,
      updatedAt: 100,
      roomId: 'private-room',
      senderId: 'parent',
      senderRole: UserRole.parent.code,
      content: 'السلام عليكم',
    );

    await tester.pumpWidget(
      ClayApp(
        app: AppIdentity.student,
        home: ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => Stream.value(session)),
            chatServiceProvider.overrideWith((ref) => service),
            chatRoomProvider('private-room')
                .overrideWith((ref) => Stream.value(room)),
            chatMessagesProvider(messagesKey)
                .overrideWith((ref) => Stream.value([message])),
          ],
          child: const ChatRoomScreen(roomId: 'private-room'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('السلام عليكم'), findsOneWidget);
    expect(find.byTooltip('كتم المحادثة'), findsOneWidget);
    await tester.tap(find.byTooltip('كتم المحادثة'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('إلغاء كتم المحادثة'), findsOneWidget);
    final member = await (db.select(
      db.chatMembers,
    )..where((row) => row.id.equals('member-parent'))).getSingle();
    expect(member.muted, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
