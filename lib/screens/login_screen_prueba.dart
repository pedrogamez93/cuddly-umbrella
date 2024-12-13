import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';



class LoginScreenprueba extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreenprueba> {

final _storage = FlutterSecureStorage();
final String clientId = '9';
final String redirectUri = 'com.example.ips_app_chileatiende://login-callback';
final String authorizationEndpoint = 'https://auth.test.chileatiende.gob.cl/oauth/authorize';
final String tokenEndpoint = 'https://auth.test.chileatiende.gob.cl/oauth/token';

String createRandomString(int length) {
  final random = Random.secure();
  final values = List<int>.generate(length, (i) => random.nextInt(256));
  return base64UrlEncode(values).substring(0, length);
}

Future<void> openLoginWebView() async {
  // Genera state y code_challenge
  String state = createRandomString(40);
  String codeVerifier = createRandomString(128);
  String challenge = base64UrlEncode(sha256.convert(utf8.encode(codeVerifier)).bytes).replaceAll('=', '');

  // Guarda el state y code_verifier en el almacenamiento seguro para su validación posterior
  await _storage.write(key: 'state', value: state);
  await _storage.write(key: 'code_verifier', value: codeVerifier);

  // Construye la URL con los parámetros necesarios
  String authUrl = "$authorizationEndpoint?client_id=$clientId&redirect_uri=$redirectUri&response_type=code&scope=*&state=$state&code_challenge=$challenge&code_challenge_method=S256&provider=azure";

  // Abre la URL en el navegador del sistema
  if (await canLaunch(authUrl)) {
    await launch(authUrl);
  } else {
    throw 'Could not launch $authUrl';
  }
}

@override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Image.asset(
                'assets/images/logo.png',
                height: 100,
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bienvenid@ al Portal interno\n de IPS ChileAtiende',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Si eres funcionari@ y quieres mantenerte informado\nsobre todo lo que está pasando en nuestra institución.',
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  openLoginWebView();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 15),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: const Text(
                  'Ingresar',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () {
                  // Acción al presionar "Olvidé mi contraseña"
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blue, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: const Text(
                  'Olvidé mi contraseña',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}