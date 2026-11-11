/// الجداول المحلية فقط التي لا تُرسل إلى الخادم.
const Set<String> localOnlyTables = {
  'outbox',
  'sync_state',
  'upload_queue',
  'device_session',
  'local_credentials',
};
