import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'local_database_service.dart';
import 'notification_manager_local_first.dart';

/// ============================================
/// BACKGROUND HANDLER
/// Saves to SQLite only - no server calls
/// ============================================
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  print('');
  print('🌙 [BG] ========================================');
  print('🌙 [BG] BACKGROUND NOTIFICATION');
  print('🌙 [BG] ID: ${message.messageId}');
  print('🌙 [BG] Title: ${message.notification?.title}');
  print('🌙 [BG] ========================================');

  try {
    final item = NotificationItem.fromFirebaseMessage(message);

    // 🔥 Save to SQLite only
    await LocalDatabaseService.insert(item.toJson());
    print('✅ [BG] Saved to SQLite');

    // Don't wait for server - app will sync when opened
  } catch (e) {
    print('❌ [BG] Error: $e');
  }

  print('🌙 [BG] Complete');
  print('');
}

/// ============================================
/// FOREGROUND HANDLER
/// Saves to SQLite and updates UI immediately
/// ============================================
void setupForegroundHandler() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    print('');
    print('🌞 [FG] ========================================');
    print('🌞 [FG] FOREGROUND NOTIFICATION');
    print('🌞 [FG] ID: ${message.messageId}');
    print('🌞 [FG] Title: ${message.notification?.title}');
    print('🌞 [FG] ========================================');

    try {
      final item = NotificationItem.fromFirebaseMessage(message);

      // 1️⃣ Add to manager (saves to SQLite + updates UI)
      await NotificationManager.instance.addNotification(item);
      print('✅ [FG] Added to manager');

      // 2️⃣ Server sync happens automatically in background
    } catch (e) {
      print('❌ [FG] Error: $e');
    }

    print('🌞 [FG] Complete');
    print('');
  });
}

/// ============================================
/// MESSAGE OPENED HANDLER
/// When user taps notification
/// ============================================
void setupMessageOpenedHandler() {
  // Handle notification tap when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('👆 [Tap] User opened notification: ${message.messageId}');
    // Navigate to notifications screen
    // This is handled in main.dart
  });

  // Handle notification tap when app was terminated
  FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
    if (message != null) {
      print('👆 [Tap] App opened from notification: ${message.messageId}');
      // Navigate to notifications screen
      // This is handled in main.dart
    }
  });
}
