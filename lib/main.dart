import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this import

import 'admin/providers/kuri_provider.dart';
import 'admin/screens/admin_home_screen.dart';
import 'admin/screens/login_page.dart';
import 'firebase_options.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --- 1. Fetch Session Data ---
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  // Retrieve saved user details
  final String savedUserId = prefs.getString('userId') ?? "";
  final String savedUserName = prefs.getString('userName') ?? "";
  final String savedUserRole = prefs.getString('userRole') ?? "Admin";

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => KuriProvider()),
      ],
      child: MyApp(
        // Pass the session data to MyApp
        isLoggedIn: isLoggedIn,
        userId: savedUserId,
        userName: savedUserName,
        userRole: savedUserRole,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  final String userId;
  final String userName;
  final String userRole;

  const MyApp({
    super.key,
    required this.isLoggedIn,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clear Grow Chits',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),


      // --- ADD THESE LINES TO FIX DATE FORMAT GLOBALLY ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'IN'), // English (India) - Uses DD/MM/YYYY
        Locale('en', 'GB'), // English (UK) - Uses DD/MM/YYYY
      ],
      locale: const Locale('en', 'IN'), // Forces the app to use this locale
      // ---------------------------------------------------

      home: isLoggedIn
          ? AdminHome(
        userId: userId,
        userName: userName,
        userRole: userRole,
      )
          : const LoginPage(),
    );
  }
}