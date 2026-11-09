import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] with [mode]; injectable for tests.
typedef ExternalLinkOpener = Future<bool> Function(Uri uri, LaunchMode mode);

Future<bool> _defaultOpener(Uri uri, LaunchMode mode) =>
    launchUrl(uri, mode: mode);

/// Merchant links (web site, Instagram, Facebook, X, directions) open outside
/// ProxiPlay: in the matching app when it is installed (Instagram, Facebook,
/// Maps), otherwise in the browser. If no external handler accepts the link,
/// the platform default is used, as before. Never throws.
///
/// ProxiPlay's own pages (legal pages, ads, notifications) keep their current
/// behaviour: they do not go through this helper.
Future<bool> openMerchantExternalLink(
  String url, {
  ExternalLinkOpener opener = _defaultOpener,
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return false;
  }
  try {
    if (await opener(uri, LaunchMode.externalApplication)) return true;
  } catch (_) {
    // Fall back to the platform default below.
  }
  try {
    return await opener(uri, LaunchMode.platformDefault);
  } catch (_) {
    return false;
  }
}
