import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:uni_links/uni_links.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final String tokenUrl = 'https://auth.test.chileatiende.gob.cl/oauth/token';
  final _storage = FlutterSecureStorage();
  String redirectUri = 'ipsapp://callback';
  String? state;
  String? verifier;
  String challenge = '';
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    setupLogin();
    _handleIncomingLinks();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String createRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64UrlEncode(values).substring(0, length);
  }

  Future<String> generateCodeChallenge(String verifier) async {
    var bytes = utf8.encode(verifier);
    var digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> setupLogin() async {
    try {
      state = createRandomString(40);
      verifier = createRandomString(128);
      challenge = await generateCodeChallenge(verifier!);

      if (state != null && verifier != null) {
        await _storage.write(key: 'state', value: state);
        await _storage.write(key: 'verifier', value: verifier);

        // Logs para verificar que el almacenamiento fue exitoso
        final storedState = await _storage.read(key: 'state');
        final storedVerifier = await _storage.read(key: 'verifier');
        print('Estado almacenado: $storedState');
        print('Verificador almacenado: $storedVerifier');
      } else {
        print('Error: No se pudo generar el estado o el verificador.');
      }
    } catch (e) {
      print('Error en setupLogin: $e');
    }
  }

  void _handleIncomingLinks() {
    _sub = uriLinkStream.listen((Uri? uri) async {
      if (uri != null && uri.toString().startsWith(redirectUri)) {
        final code = uri.queryParameters['code'];
        final receivedState = uri.queryParameters['state'];

        // Logs para depuración
        print('Callback URI recibido: $uri');
        print('Código recibido: $code');
        print('Estado recibido: $receivedState');

        await _verifyAndExchangeCode(code, receivedState);
      }
    }, onError: (err) {
      print('Error listening to links: $err');
    });
  }

  Future<void> _verifyAndExchangeCode(String? code, String? receivedState) async {
    try {
      final storedState = await _storage.read(key: 'state');

      // Logs para depuración
      print('Estado almacenado para verificar: $storedState');
      print('Estado recibido en el callback: $receivedState');

      if (code != null && receivedState == storedState) {
        final params = {
          'client_id': '27',
          'redirect_uri': redirectUri,
          'code_verifier': verifier ?? '',
          'code': code,
          'grant_type': 'authorization_code',
        };

        final response = await http.post(
          Uri.parse(tokenUrl),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: params,
        );

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);

          await _storage.write(key: 'access_token', value: responseData['access_token']);
          await _storage.write(key: 'refresh_token', value: responseData['refresh_token']);

          print('Autenticación exitosa, tokens almacenados.');
          print('token: ${responseData['access_token']}');
          Navigator.pushReplacementNamed(context, '/logged_in_screen');
        } else {
          print('Error en la autenticación: ${response.statusCode} ${response.body}');
        }
      } else {
        print('Error: Estado no coincide o falta el código.');
      }
    } catch (e) {
      print('Error al verificar o intercambiar el código: $e');
    }
  }

  Future<void> _launchAuthUrl() async {
    final authUrl = "https://auth.test.chileatiende.gob.cl/oauth/authorize"
        "?client_id=27"
        "&redirect_uri=$redirectUri"
        "&response_type=code"
        "&scope=*"
        "&state=$state"
        "&code_challenge=$challenge"
        "&code_challenge_method=S256"
        "&provider=azure";

    try {
      if (await canLaunch(authUrl)) {
        await launch(authUrl);
      } else {
        print('No se pudo abrir la URL de autenticación: $authUrl');
      }
    } catch (e) {
      print('Error al lanzar la URL de autenticación: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Bienvenido, por favor inicie sesión.',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _launchAuthUrl,
              child: Text('Iniciar sesión con Active Directory'),
            ),
          ],
        ),
      ),
    );
  }
}