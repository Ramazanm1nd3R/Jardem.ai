import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';

void main() {
  group('normalizeKzPhone', () {
    test('accepts the usual spellings', () {
      expect(normalizeKzPhone('+7 777 123 45 67'), '77771234567');
      expect(normalizeKzPhone('+77771234567'), '77771234567');
      expect(normalizeKzPhone('8 (777) 123-45-67'), '77771234567');
      expect(normalizeKzPhone('7771234567'), '77771234567');
      expect(normalizeKzPhone('77771234567'), '77771234567');
      expect(normalizeKzPhone('  +7 701 234 56 78 '), '77012345678');
    });

    test('8 is only a trunk prefix for 11-digit numbers', () {
      expect(normalizeKzPhone('8001234567'), '78001234567');
      expect(normalizeKzPhone('87001234567'), '77001234567');
    });

    test('rejects wrong lengths', () {
      expect(normalizeKzPhone(null), isNull);
      expect(normalizeKzPhone(''), isNull);
      expect(normalizeKzPhone('+7 '), isNull);
      expect(normalizeKzPhone('+7 777 123 45 6'), isNull);
      expect(normalizeKzPhone('+7 777 123 45 678'), isNull);
      expect(normalizeKzPhone('123456789'), isNull);
      expect(normalizeKzPhone('112'), isNull);
    });

    test('a plus must lead and makes the country code explicit', () {
      expect(normalizeKzPhone('+7771234567'), isNull);
      expect(normalizeKzPhone('+87771234567'), isNull);
      expect(normalizeKzPhone('7+7771234567'), isNull);
      expect(normalizeKzPhone('+7 777 123 45 67+'), isNull);
      expect(normalizeKzPhone('++77771234567'), isNull);
    });

    test('rejects other country codes', () {
      expect(normalizeKzPhone('+1 777 123 45 67'), isNull);
      expect(normalizeKzPhone('97771234567'), isNull);
    });

    test('rejects letters and stray symbols', () {
      expect(normalizeKzPhone('+7 777 123 45 6a'), isNull);
      expect(normalizeKzPhone('+7 777 abc 45 67'), isNull);
      expect(normalizeKzPhone('+7 777 123 45 67 доб. 1'), isNull);
      expect(normalizeKzPhone('+7_777_123_45_67'), isNull);
      expect(normalizeKzPhone('+7 777*123 45 67'), isNull);
      expect(normalizeKzPhone('+7 777,123,45,67'), isNull);
      expect(normalizeKzPhone('+7.777.123.45.67'), isNull);
    });
  });

  test('isValidKzPhone mirrors normalisation', () {
    expect(isValidKzPhone('+7 777 123 45 67'), isTrue);
    expect(isValidKzPhone('8 777 123 45 67'), isTrue);
    expect(isValidKzPhone('+7 777'), isFalse);
    expect(isValidKzPhone(null), isFalse);
  });

  group('formatKzPhone', () {
    test('formats valid numbers', () {
      expect(formatKzPhone('87771234567'), '+7 777 123 45 67');
      expect(formatKzPhone('+7(701)234-56-78'), '+7 701 234 56 78');
      expect(formatKzPhone('7001234589'), '+7 700 123 45 89');
    });

    test('returns invalid input trimmed and unchanged', () {
      expect(formatKzPhone('  12345 '), '12345');
      expect(formatKzPhone(null), '');
    });
  });

  group('telUri', () {
    test('short numbers', () {
      expect(telUri('112').toString(), 'tel:112');
      expect(telUri(' 103 ').toString(), 'tel:103');
    });

    test('keeps a leading plus and strips formatting', () {
      expect(telUri('+7 777 123 45 67').toString(), 'tel:+77771234567');
      expect(telUri('8 (777) 123-45-67').toString(), 'tel:87771234567');
      expect(telUri('+7 777 123 45 67').scheme, 'tel');
    });
  });
}
