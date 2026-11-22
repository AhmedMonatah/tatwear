/// Safely converts a dynamic value to a String
String getSafeString(dynamic value, [String fallback = 'غير معروف']) {
  if (value == null) return fallback;
  if (value is String) return value.isNotEmpty ? value : fallback;
  return value.toString().isNotEmpty ? value.toString() : fallback;
}

/// Safely converts a dynamic value to a double
double getSafeDouble(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
