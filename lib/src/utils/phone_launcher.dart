import 'package:url_launcher/url_launcher.dart';

String normalizePhoneNumber(String rawPhoneNumber) {
  final trimmedPhoneNumber = rawPhoneNumber.trim();
  if (trimmedPhoneNumber.isEmpty) {
    return '';
  }

  final hasLeadingPlus = trimmedPhoneNumber.startsWith('+');
  final digitsOnly = trimmedPhoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) {
    return '';
  }

  return hasLeadingPlus ? '+$digitsOnly' : digitsOnly;
}

Future<bool> launchPhoneNumber(String rawPhoneNumber) async {
  final normalizedPhoneNumber = normalizePhoneNumber(rawPhoneNumber);
  if (normalizedPhoneNumber.isEmpty) {
    return false;
  }

  final dialerUri = Uri.parse('tel:$normalizedPhoneNumber');
  return launchUrl(dialerUri, mode: LaunchMode.externalApplication);
}
