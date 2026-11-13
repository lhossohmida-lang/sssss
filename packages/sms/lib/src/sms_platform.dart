import 'package:flutter/services.dart';
import 'package:school_core/school_core.dart';

import 'sms_queue_service.dart';

/// شريحة SIM ظاهرة للجهاز.
class SmsSimCard {
  const SmsSimCard({
    required this.slotIndex,
    required this.subscriptionId,
    required this.displayName,
    required this.carrierName,
  });

  final int slotIndex;
  final int subscriptionId;
  final String displayName;
  final String carrierName;

  factory SmsSimCard.fromMap(Map<Object?, Object?> map) => SmsSimCard(
    slotIndex: map['slotIndex']! as int,
    subscriptionId: map['subscriptionId']! as int,
    displayName: map['displayName']! as String,
    carrierName: map['carrierName']! as String,
  );
}

/// عمليات Android المطلوبة لإرسال الرسائل وعرض حالة الإرسال للمستخدم.
abstract interface class SmsDispatchPlatform {
  Future<bool> requestPermissions();

  Future<List<SmsSimCard>> availableSimCards();

  Future<void> startForegroundService();

  Future<void> stopForegroundService();

  Future<void> send(SmsQueueRow message, {required int simSlotIndex});
}

/// ربط Flutter بقناة Android المسؤولة عن `SmsManager` والخدمة الأمامية.
class AndroidSmsPlatform implements SmsDispatchPlatform {
  AndroidSmsPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'dz.school.admin/sms';
  final MethodChannel _channel;

  @override
  Future<bool> requestPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
    } on PlatformException catch (error) {
      throw _asTransportException(error);
    }
  }

  @override
  Future<List<SmsSimCard>> availableSimCards() async {
    try {
      final values = await _channel.invokeListMethod<Object?>(
        'availableSimCards',
      );
      return [
        for (final value in values ?? const <Object?>[])
          SmsSimCard.fromMap(Map<Object?, Object?>.from(value! as Map)),
      ];
    } on PlatformException catch (error) {
      throw _asTransportException(error);
    }
  }

  @override
  Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod<void>('startForegroundService');
    } on PlatformException catch (error) {
      throw _asTransportException(error);
    }
  }

  @override
  Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod<void>('stopForegroundService');
    } on PlatformException catch (error) {
      throw _asTransportException(error);
    }
  }

  @override
  Future<void> send(SmsQueueRow message, {required int simSlotIndex}) async {
    try {
      await _channel.invokeMethod<void>('send', {
        'id': message.id,
        'phone': message.phone,
        'body': message.message,
        'simSlotIndex': simSlotIndex,
      });
    } on PlatformException catch (error) {
      throw _asTransportException(error);
    }
  }

  SmsTransportException _asTransportException(PlatformException error) {
    const permanentCodes = {
      'permission_denied',
      'sim_not_found',
      'no_telephony',
      'invalid_phone',
      'empty_message',
      'sim_selection_required',
    };
    return SmsTransportException(
      error.message ?? error.code,
      retryable: !permanentCodes.contains(error.code),
    );
  }
}
