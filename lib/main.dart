import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ips_app_chileatiende/screens/logged_in_screen.dart';
import 'package:ips_app_chileatiende/screens/login_screen.dart';
import 'package:ips_app_chileatiende/widgets/base_screen.dart'; // Importa BaseScreen
import 'dart:developer';
import 'package:ips_app_chileatiende/screens/profile_screen.dart';

void main() {
  // Configura HttpOverrides para ignorar verificación SSL
  HttpOverrides.global = MyHttpOverrides();
  

  runZonedGuarded(() {
    runApp(MyApp());
  }, (error, stackTrace) {
    log('Error: $error');
    log('StackTrace: $stackTrace');
  });
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Auth',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/', // Pantalla inicial es LoginScreen
      routes: {
        '/': (context) => LoginScreen(), // LoginScreen independiente
        '/home': (context) => BaseScreen(), // BaseScreen con los menús
        '/profile': (context) => ProfileScreen(), // Agrega ProfileScreen
      },
    );
  }
}