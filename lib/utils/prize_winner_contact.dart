import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Winner contact info for a prize, fetched through the
/// `getPrizeWinnerContactForMerchant` Cloud Function rather than reading
/// `users/{winner_id}` directly — the CF verifies server-side that the
/// caller is the merchant owning this prize (or an admin) before returning
/// name/email/phone, so the client never needs read access to another
/// user's profile document.
class PrizeWinnerContact {
  const PrizeWinnerContact({
    required this.firstName,
    required this.lastName,
    required this.city,
    required this.email,
    required this.phoneNumber,
  });

  final String firstName;
  final String lastName;
  final String city;
  final String email;
  final String phoneNumber;

  String get fullName =>
      [firstName, lastName].where((part) => part.trim().isNotEmpty).join(' ');
}

/// Caches one in-flight/resolved contact request per prize for the lifetime of
/// its owner screen. Rebuilds therefore do not issue duplicate callables.
class PrizeWinnerContactFutureCache {
  PrizeWinnerContactFutureCache({
    required Future<PrizeWinnerContact?> Function(String prizeId) fetch,
  }) : _fetch = fetch;

  final Future<PrizeWinnerContact?> Function(String prizeId) _fetch;
  final Map<String, Future<PrizeWinnerContact?>> _contacts = {};

  Future<PrizeWinnerContact?> get(String prizeId) =>
      _contacts.putIfAbsent(prizeId, () => _fetch(prizeId));

  void retry(String prizeId) => _contacts.remove(prizeId);
}

/// Returns a completed contact (which may contain empty individual fields).
/// Callable errors are rethrown so merchant UI can present an explicit retry.
Future<PrizeWinnerContact?> fetchPrizeWinnerContactForMerchant(
  String prizeId,
) async {
  try {
    final result = await FirebaseFunctions.instance
        .httpsCallable('getPrizeWinnerContactForMerchant')
        .call({'prizeId': prizeId}).timeout(const Duration(seconds: 15));
    final data = result.data;
    if (data is! Map) {
      return null;
    }
    String field(String key) => (data[key] ?? '').toString();
    return PrizeWinnerContact(
      firstName: field('firstName'),
      lastName: field('lastName'),
      city: field('city'),
      email: field('email'),
      phoneNumber: field('phoneNumber'),
    );
  } on FirebaseFunctionsException catch (error) {
    if (kDebugMode) {
      debugPrint('[PrizeWinnerContact] fetch failed code=${error.code}');
    }
    rethrow;
  } catch (_) {
    if (kDebugMode) debugPrint('[PrizeWinnerContact] error_or_timeout');
    rethrow;
  }
}
