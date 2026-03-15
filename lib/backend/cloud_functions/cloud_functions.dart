import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

Future<Map<String, dynamic>> makeCloudCall(
  String callName,
  Map<String, dynamic> input,
) async {
  try {
    // Use us-central1 region explicitly (where functions are deployed)
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final response = await functions
        .httpsCallable(callName, options: HttpsCallableOptions())
        .call(input);
    return response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : {};
  } on FirebaseFunctionsException {
    if (kDebugMode) {
      debugPrint('Cloud function error');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Cloud function error');
    }
  }
  return {};
}
