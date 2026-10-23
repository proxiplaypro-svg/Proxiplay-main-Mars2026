import 'package:firebase_core/firebase_core.dart';

/// Only an explicitly requested emulator session can replace the project ID.
FirebaseOptions isolatedEmulatorOptions(
  FirebaseOptions options, {
  required bool emulatorsEnabled,
  required String requestedProjectId,
}) {
  final projectId = requestedProjectId.trim();
  if (projectId.isEmpty) return options;
  if (!emulatorsEnabled || !RegExp(r'^demo-[a-z0-9-]+$').hasMatch(projectId)) {
    throw StateError('An isolated demo project requires debug Firebase emulators.');
  }
  return options.copyWith(
    projectId: projectId,
    storageBucket: '$projectId.appspot.com',
    authDomain: '$projectId.firebaseapp.com',
  );
}
