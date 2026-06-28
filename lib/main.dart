import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';
import 'providers/parent_provider.dart';
import 'providers/child_provider.dart';
import 'providers/alert_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/web_pos_screen.dart';
import 'services/notification_service.dart';

// Top-level background message handler — must live outside any class
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) =>
    firebaseMessagingBackgroundHandler(message);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register background FCM handler before Firebase.initializeApp
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      debugPrint('✓ Firebase initialized successfully');
    } else {
      debugPrint('✓ Firebase already initialized (hot reload detected)');
    }
  } catch (e) {
    debugPrint('❌ Firebase initialization error: $e');
  }

  // Initialize local notifications + FCM permissions
  await NotificationService.initialize();

  runApp(const KidGuardApp());
}

class KidGuardApp extends StatelessWidget {
  const KidGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ParentProvider()),
        ChangeNotifierProvider(create: (_) => ChildProvider()..loadChildren()),
        ChangeNotifierProvider(create: (_) => AlertProvider()),
      ],
      child: MaterialApp(
        title: 'KidGuard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFFFFCF6),
          primaryColor: const Color(0xFF5C8DFF),
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF5C8DFF),
            secondary: Color(0xFFFFB86C),
            surface: Colors.white,
          ),
          cardColor: Colors.white,
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFFFF8F0),
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            titleTextStyle: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
            iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF0F0F0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF4A90D9), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE53935)),
            ),
            hintStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90D9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              elevation: 0,
            ),
          ),
          useMaterial3: true,
        ),
        home: kIsWeb ? const WebPosScreen() : const SplashScreen(),
      ),
    );
  }
}
