import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ips_app_chileatiende/screens/login_screen.dart';
import 'package:ips_app_chileatiende/screens/profile_screen.dart';
import 'package:ips_app_chileatiende/widgets/base_screen.dart';

void main() async {
  // Inicializa bindings en la MISMA zona en la que luego llamas runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Manejo global de errores (recomendado en Web en lugar de runZonedGuarded)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    developer.log(
      'FlutterError',
      name: 'main',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    developer.log('Uncaught platform error', name: 'main', error: error, stackTrace: stack);
    return true; // evita relanzar
  };

  // Ajustes de UI solo para plataformas no-Web
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );

    // ⚠️ Si en QA necesitas ignorar certificados inválidos,
    // crea un helper con import condicional y actívalo solo en dev:
    // if (!kReleaseMode) {
    //   http_overrides.setupBadCertHttpOverrides();
    // }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Auth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 18),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const LoginScreen(),
        '/home': (_) => BaseScreen(),
        '/profile': (_) => ProfileScreen(),
      },
    );
  }
}
