import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  group('LoginCredentials', () {
    test('البريد يُبنى من رقم الهاتف بكل صيغه', () {
      for (final phone in [
        '0550123456',
        '055 012 34 56',
        '+213550123456',
        '00213550123456',
        '0550-12-34-56',
      ]) {
        expect(
          LoginCredentials.emailForPhone(phone),
          '0550123456@school.local',
          reason: phone,
        );
      }
    });

    test('رقم غير صالح يرمي FormatException', () {
      for (final phone in ['', '0150123456', '055012345', 'abc']) {
        expect(
          () => LoginCredentials.emailForPhone(phone),
          throwsFormatException,
          reason: phone,
        );
      }
    });

    test('كلمة السر المولَّدة: 8 رموز من الحروف المقروءة فقط', () {
      final random = Random(7);
      final seen = <String>{};
      for (var i = 0; i < 500; i++) {
        final password = LoginCredentials.generatePassword(random: random);
        expect(password.length, LoginCredentials.generatedPasswordLength);
        for (final char in password.split('')) {
          expect(LoginCredentials.passwordAlphabet, contains(char));
        }
        expect(RegExp('[0O1IL]').hasMatch(password), isFalse);
        expect(LoginCredentials.passwordProblem(password), isNull);
        seen.add(password);
      }
      expect(seen.length, greaterThan(490));
    });

    test('نفس البذرة تعطي نفس كلمة السر', () {
      expect(
        LoginCredentials.generatePassword(random: Random(1)),
        LoginCredentials.generatePassword(random: Random(1)),
      );
    });

    test('generateFor يعطي بريداً وكلمة سر', () {
      final credentials = LoginCredentials.generateFor(
        '0661234567',
        random: Random(3),
      );
      expect(credentials.email, '0661234567@school.local');
      expect(credentials.password.length, 8);
    });

    test('التحقق من كلمة السر', () {
      expect(LoginCredentials.passwordProblem(''), isNotNull);
      expect(LoginCredentials.passwordProblem('1234567'), isNotNull);
      expect(LoginCredentials.passwordProblem(' 12345678'), isNotNull);
      expect(LoginCredentials.passwordProblem('12345678 '), isNotNull);
      expect(LoginCredentials.passwordProblem('12345678'), isNull);
      expect(LoginCredentials.passwordProblem('كلمة سر طويلة'), isNull);
    });

    test('التحقق من البريد وتوحيده', () {
      expect(LoginCredentials.normalizeEmail('  A@B.com '), 'a@b.com');
      expect(LoginCredentials.isValidEmail('0550123456@school.local'), isTrue);
      expect(LoginCredentials.isValidEmail('Admin@Example.com'), isTrue);
      for (final bad in ['', 'abc', 'a@b', '@b.com', 'a b@c.com']) {
        expect(LoginCredentials.isValidEmail(bad), isFalse, reason: bad);
        expect(LoginCredentials.emailProblem(bad), isNotNull);
      }
      expect(LoginCredentials.emailProblem('a@b.com'), isNull);
    });
  });

  group('خانة الدخول: رقم الهاتف أو البريد', () {
    test('الهاتف بكل صيغه يصير بريد الدخول', () {
      for (final input in [
        '0550123456',
        ' 0550123456 ',
        '055 012 34 56',
        '+213550123456',
        '00213550123456',
        '0550-12-34-56',
        '٠٥٥٠١٢٣٤٥٦', // أرقام عربية-هندية
        '۰۵۵۰۱۲۳۴۵۶', // أرقام فارسية
        '\u{200E}0550123456\u{200F}', // علامات اتجاه خفية من النسخ
      ]) {
        expect(
          LoginCredentials.emailFromIdentifier(input),
          '0550123456@school.local',
          reason: input,
        );
        expect(LoginCredentials.identifierProblem(input), isNull);
      }
    });

    test('البريد الكامل يبقى بريداً موحَّداً', () {
      expect(
        LoginCredentials.emailFromIdentifier('  Owner@School.com '),
        'owner@school.com',
      );
      expect(
        LoginCredentials.emailFromIdentifier('0550123456@school.local'),
        '0550123456@school.local',
      );
    });

    test('المدخل الخاطئ يعطي null وسبباً بالعربية', () {
      for (final bad in [
        '',
        '   ',
        '12345',
        '0150123456',
        'abc',
        'a@b',
        '@x.com',
      ]) {
        expect(LoginCredentials.emailFromIdentifier(bad), isNull, reason: bad);
        expect(LoginCredentials.identifierProblem(bad), isNotNull, reason: bad);
      }
      expect(LoginCredentials.identifierProblem(''), 'أدخل رقم الهاتف');
      expect(
        LoginCredentials.identifierProblem('12345'),
        contains('يبدأ بـ 05 أو 06 أو 07'),
      );
    });

    test('اسم الدخول المعروض: الهاتف للبريد المولَّد وإلا البريد نفسه', () {
      expect(
        LoginCredentials.displayLogin('0550123456@school.local'),
        '0550123456',
      );
      expect(
        LoginCredentials.displayLogin('0550123456@SCHOOL.local'),
        '0550123456',
      );
      expect(
        LoginCredentials.displayLogin('owner@school.com'),
        'owner@school.com',
      );
      expect(
        LoginCredentials.displayLogin('abc@school.local'),
        'abc@school.local',
      );
      expect(
        LoginCredentials.phoneOfEmail('0550123456@school.local'),
        '0550123456',
      );
      expect(LoginCredentials.phoneOfEmail('owner@school.com'), isNull);
    });
  });
}
