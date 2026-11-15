import 'package:intl/intl.dart';

final _whole = NumberFormat.decimalPattern('en');

String whole(num value) => _whole.format(value);

bool isOlder(String current, String minimum) {
  List<int> parts(String value) => value.split('+').first.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final a = parts(current);
  final b = parts(minimum);
  for (var index = 0; index < 3; index++) {
    final left = index < a.length ? a[index] : 0;
    final right = index < b.length ? b[index] : 0;
    if (left != right) {
      return left < right;
    }
  }
  return false;
}

/// Book cover colours arrive from the library as #RRGGBB.
int colourValue(Object? hex, int fallback) {
  final text = (hex ?? '').toString().replaceAll('#', '');
  final parsed = text.length == 6 ? int.tryParse(text, radix: 16) : null;
  return parsed == null ? fallback : 0xFF000000 | parsed;
}
