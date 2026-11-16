import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database.dart';
import 'file_store.dart';
import 'postgrest_remote_store.dart';
import 'remote_store.dart';
import 'synced_tables.dart';

/// البث اللحظي عبر Supabase Realtime: كل إضافة أو تحديث في أي جدول مزامَن
/// يصل كصف كامل ويُطبَّق محلياً بقاعدة «آخر تعديل يفوز».
class SupabaseRealtimeSource implements RealtimeSource {
  SupabaseRealtimeSource(this.client, {required this.tables});

  final SupabaseClient client;

  /// أسماء الجداول التي يُستمع إليها.
  final List<String> tables;

  @override
  Stream<RemoteChange> changes() {
    // ignore: close_sinks, يُغلق في onCancel عند إلغاء الاشتراك.
    late final StreamController<RemoteChange> controller;
    RealtimeChannel? channel;

    controller = StreamController<RemoteChange>(
      onListen: () {
        final allowed = tables.toSet();
        channel = client
            .channel('school-sync')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              callback: (payload) {
                if (payload.eventType == PostgresChangeEvent.delete) return;
                if (!allowed.contains(payload.table)) return;
                controller.add(
                  RemoteChange(
                    table: payload.table,
                    row: Map<String, Object?>.from(payload.newRecord),
                  ),
                );
              },
            )
            .subscribe((status, error) {
              if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                controller.addError(
                  RemoteException(
                    'انقطع البث اللحظي${error == null ? '' : ': $error'}',
                    permanent: false,
                  ),
                );
              }
            });
      },
      onCancel: () async {
        final active = channel;
        if (active != null) await client.removeChannel(active);
        await controller.close();
      },
    );
    return controller.stream;
  }
}

/// مخزن الملفات على Supabase Storage.
class SupabaseFileStore implements FileStore {
  SupabaseFileStore(this.client);

  final SupabaseClient client;

  @override
  Future<String> upload({
    required String bucket,
    required String remotePath,
    required String localPath,
  }) async {
    try {
      await client.storage
          .from(bucket)
          .upload(
            remotePath,
            File(localPath),
            fileOptions: const FileOptions(upsert: true),
          );
      return '$bucket/$remotePath';
    } on StorageException catch (e) {
      throw RemoteException(e.message, permanent: _isPermanent(e.statusCode));
    } on SocketException {
      throw const RemoteException('لا يوجد اتصال بالإنترنت', permanent: false);
    } on TimeoutException {
      throw const RemoteException('انتهت مهلة الاتصال', permanent: false);
    }
  }

  @override
  Future<Uint8List> download({
    required String bucket,
    required String remotePath,
  }) async {
    try {
      return await client.storage.from(bucket).download(remotePath);
    } on StorageException catch (e) {
      throw RemoteException(e.message, permanent: _isPermanent(e.statusCode));
    } on SocketException {
      throw const RemoteException('لا يوجد اتصال بالإنترنت', permanent: false);
    } on TimeoutException {
      throw const RemoteException('انتهت مهلة الاتصال', permanent: false);
    }
  }

  static bool _isPermanent(String? statusCode) {
    final status = int.tryParse(statusCode ?? '');
    if (status == null) return false;
    return status >= 400 &&
        status < 500 &&
        status != 401 &&
        status != 408 &&
        status != 429;
  }
}

/// يبني مكوّنات الخادم الثلاثة (REST، البث، الملفات) من عميل Supabase واحد.
class SupabaseBackend {
  /// [apiKey] هو المفتاح العام نفسه الذي هُيِّئ به [client]. لا يُقرأ من ترويسات العميل:
  /// مكتبة Supabase تضيف `apikey` لكل طلب في طبقتها ولا تضعه في `rest.headers`، فكان
  /// المخزن يرسل مفتاحاً فارغاً ويرفضه الخادم بـ401 في كل طلب (كشفه اختبار الخادم
  /// الحقيقي في 8.2).
  SupabaseBackend(
    this.client, {
    required AppDatabase db,
    required String apiKey,
  }) : remote = PostgrestRemoteStore(
         restUrl: client.rest.url,
         apiKey: _requireKey(apiKey),
         accessToken: () async => client.auth.currentSession?.accessToken,
         primaryKeys: PostgrestRemoteStore.primaryKeysOf(db),
       ),
       realtime = SupabaseRealtimeSource(
         client,
         tables: [
           for (final table in db.allTables)
             if (!localOnlyTables.contains(table.actualTableName))
               table.actualTableName,
         ],
       ),
       files = SupabaseFileStore(client);

  final SupabaseClient client;
  final RemoteStore remote;
  final RealtimeSource realtime;
  final FileStore files;

  static String _requireKey(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'apiKey', 'المفتاح العام مطلوب');
    }
    return key;
  }
}
