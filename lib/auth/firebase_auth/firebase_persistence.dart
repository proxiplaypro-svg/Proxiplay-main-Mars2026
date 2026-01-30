import 'package:firebase_auth/firebase_auth.dart';

/// Firebase persistence handler for managing app session persistence
/// 
/// Firebase Auth automatically persists user sessions on mobile and web platforms.
/// This class provides utilities to ensure proper session management.
class FirebasePersistenceManager {
  static final FirebasePersistenceManager _instance =
      FirebasePersistenceManager._internal();

  factory FirebasePersistenceManager() {
    return _instance;
  }

  FirebasePersistenceManager._internal();

  /// Initialize Firebase persistence settings
  /// 
  /// This should be called early in the app lifecycle to ensure
  /// that user sessions are properly maintained across app restarts.
  /// 
  /// Firebase automatically persists sessions on:
  /// - iOS: Uses persistent storage in UserDefaults
  /// - Android: Uses SharedPreferences
  /// - Web: Uses localStorage/sessionStorage
  Future<void> initializePersistence() async {
    try {
      // Firebase Auth persistence is enabled by default on mobile and web
      // This method can be used for any additional setup if needed in the future
      
      // Check if a user is already signed in (from persistent storage)
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser != null) {
        // User session exists - refresh to ensure it's still valid
        await currentUser.reload();
      }
    } catch (e) {
      print('Error initializing Firebase persistence: $e');
    }
  }

  /// Clear all Firebase persistence data when user logs out
  /// 
  /// This ensures that no user data remains in the device's persistent storage
  /// after logout.
  Future<void> clearPersistentSession() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      print('Error clearing persistent session: $e');
    }
  }

  /// Check if a user session exists in persistent storage
  /// 
  /// Returns true if a user is already logged in (either from current session
  /// or from persistent storage).
  bool hasPersistedSession() {
    return FirebaseAuth.instance.currentUser != null;
  }

  /// Get the current persisted user if one exists
  User? getPersistedUser() {
    return FirebaseAuth.instance.currentUser;
  }
}
