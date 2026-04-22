import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Console roles for admin / emergency services / hospital / fleet entry.
enum StaffConsoleRole { admin, emergencyServices, hospital }

/// EmergencyOS: StaffSessionService in lib/services/staff_session_service.dart.
class StaffSessionService {
  static const _prefKey = 'staff_console_role_v1';

  static Future<StaffConsoleRole?> loadRole() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey);
      if (raw == 'admin') return StaffConsoleRole.admin;
      if (raw == 'emergency') return StaffConsoleRole.emergencyServices;
      if (raw == 'hospital') return StaffConsoleRole.hospital;
    } catch (e) {
      debugPrint('[StaffSession] loadRole: $e');
    }
    return null;
  }

  static Future<void> setRole(StaffConsoleRole role) async {
    try {
      final p = await SharedPreferences.getInstance();
      String value;
      switch (role) {
        case StaffConsoleRole.admin:
          value = 'admin';
        case StaffConsoleRole.emergencyServices:
          value = 'emergency';
        case StaffConsoleRole.hospital:
          value = 'hospital';
      }
      await p.setString(_prefKey, value);
    } catch (e) {
      debugPrint('[StaffSession] setRole: $e');
    }
  }

  static Future<void> clearRole() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefKey);
    } catch (e) {
      debugPrint('[StaffSession] clearRole: $e');
    }
  }

  /// Firestore rules require an authenticated user. Anonymous sign-in is enough for ops consoles.
  static Future<User?> ensureFirebaseUserForConsole() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser;
    try {
      final cred = await auth.signInAnonymously();
      return cred.user;
    } catch (e) {
      debugPrint('[StaffSession] signInAnonymously failed: $e');
      rethrow;
    }
  }
}
