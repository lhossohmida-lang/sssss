import 'package:supabase_flutter/supabase_flutter.dart';

/// Server storage for the current account's Firebase Installation ID (FID).
/// Installation IDs stay outside the replicated local tables.
abstract interface class PushInstallationStore {
  Future<void> register({
    required String accountId,
    required String installationId,
    required String platform,
    required int updatedAt,
  });

  Future<void> unregister({
    required String accountId,
    required String installationId,
  });
}

class SupabasePushInstallationStore implements PushInstallationStore {
  SupabasePushInstallationStore(this.client);

  final SupabaseClient client;

  @override
  Future<void> register({
    required String accountId,
    required String installationId,
    required String platform,
    required int updatedAt,
  }) async {
    await client.from('push_installations').upsert({
      'user_id': accountId,
      'installation_id': installationId,
      'platform': platform,
      'updated_at': updatedAt,
    }, onConflict: 'installation_id');
  }

  @override
  Future<void> unregister({
    required String accountId,
    required String installationId,
  }) async {
    await client
        .from('push_installations')
        .delete()
        .eq('user_id', accountId)
        .eq('installation_id', installationId);
  }
}
