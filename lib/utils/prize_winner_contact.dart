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

/// Returns `null` if the call fails or the caller isn't authorized — callers
/// should show a neutral fallback ("coordonnées indisponibles") rather than
/// surfacing the raw error.
Future<PrizeWinnerContact?> fetchPrizeWinnerContactForMerchant(
  String prizeId,
) async {
  try {
    final result = await FirebaseFunctions.instance
        .httpsCallable('getPrizeWinnerContactForMerchant')
        .call({'prizeId': prizeId});
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
    debugPrint(
      '[PrizeWinnerContact] fetch failed prizeId=$prizeId '
      'code=${error.code} message=${error.message}',
    );
    return null;
  } catch (error) {
    debugPrint('[PrizeWinnerContact] fetch failed prizeId=$prizeId error=$error');
    return null;
  }
}
