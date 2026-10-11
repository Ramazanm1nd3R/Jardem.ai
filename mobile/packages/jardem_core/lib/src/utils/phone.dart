/// Kazakhstan (+7) phone number helpers.
library;

/// Digits of a +7 number as `7XXXXXXXXXX`, or null if [input] is not one.
///
/// Accepts `+7 777 123 45 67`, `8 (777) 123-45-67`, `7771234567`. With a leading
/// plus the country code must be spelled out, so `+8…` and short `+7…` fail.
String? normalizeKzPhone(String? input) {
  if (input == null) return null;
  final text = input.trim();
  if (RegExp(r'[^\d\s()+\-]').hasMatch(text)) return null;
  // A plus may only lead the number, and then the country code is explicit.
  final international = text.startsWith('+');
  if (text.lastIndexOf('+') > 0) return null;
  var digits = text.replaceAll(RegExp(r'\D'), '');
  if (!international) {
    if (digits.length == 10) {
      digits = '7$digits';
    } else if (digits.length == 11 && digits.startsWith('8')) {
      digits = '7${digits.substring(1)}';
    }
  }
  if (digits.length != 11 || !digits.startsWith('7')) return null;
  return digits;
}

bool isValidKzPhone(String? input) => normalizeKzPhone(input) != null;

/// `+7 777 123 45 67`; returns the trimmed input unchanged when it is not valid.
String formatKzPhone(String? input) {
  final d = normalizeKzPhone(input);
  if (d == null) return (input ?? '').trim();
  return '+7 ${d.substring(1, 4)} ${d.substring(4, 7)} ${d.substring(7, 9)} ${d.substring(9, 11)}';
}

/// `tel:` URI for a dialler: keeps digits and a leading plus.
Uri telUri(String number) {
  final trimmed = number.trim();
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  return Uri(scheme: 'tel', path: trimmed.startsWith('+') ? '+$digits' : digits);
}
