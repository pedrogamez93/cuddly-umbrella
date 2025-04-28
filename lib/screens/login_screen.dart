import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:uni_links/uni_links.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

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
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    setupLogin();
    _handleIncomingLinks();

    Timer.periodic(Duration(minutes: 15), (timer) async {
      if (await _isTokenExpiringSoon()) {
        await _refreshAccessToken();
      }
    });
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
        await _verifyAndExchangeCode(code, receivedState, context);
      }
    }, onError: (err) {
      print('Error listening to links: $err');
    });
  }

  Future<void> _verifyAndExchangeCode(String? code, String? receivedState, BuildContext context) async {
    setState(() => isLoading = true); 
    try {
      final storedState = await _storage.read(key: 'state');
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
          String accessToken = responseData['access_token'];

          await _storage.write(key: 'access_token', value: accessToken);
          await _storage.write(key: 'refresh_token', value: responseData['refresh_token']);
            print('🔑 Token completo:');
            for (int i = 0; i < accessToken.length; i += 100) {
              final endIdx = (i + 100 > accessToken.length) ? accessToken.length : i + 100;
              print(accessToken.substring(i, endIdx));
            }


          Map<String, dynamic> decodedToken = JwtDecoder.decode(accessToken);
          String userEmail = decodedToken['email'];
          await _storage.write(key: 'user_email', value: userEmail);

          String fullName = decodedToken['nombre_completo'];
          await _storage.write(key: 'user_full_name', value: fullName);

          if (decodedToken.containsKey('photo') && decodedToken['photo'] != null) {
            String photoUrl = decodedToken['photo'];
            await _storage.write(key: 'user_photo', value: photoUrl);
          }

          await _fetchUserIdByEmail(userEmail);
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          print('Error en la autenticación: ${response.statusCode} ${response.body}');
        }
      } else {
        print('Error: Estado no coincide o falta el código.');
      }
    } catch (e) {
      print('Error al verificar o intercambiar el código: $e');
    } finally {
      setState(() => isLoading = false); // Desactivar preloader
    }
  }

  Future<bool> _isTokenExpiringSoon() async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) return true;

    final decodedToken = JwtDecoder.decode(accessToken);
    final expirationDate = JwtDecoder.getExpirationDate(accessToken);
    final remainingTime = expirationDate.difference(DateTime.now());

    return remainingTime.inMinutes < 5;
  }

  Future<void> _refreshAccessToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) {
        print('No se encontró el refresh_token. El usuario debe autenticarse de nuevo.');
        return;
      }

      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': '27',
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final newAccessToken = responseData['access_token'];
        final newRefreshToken = responseData['refresh_token'];

        await _storage.write(key: 'access_token', value: newAccessToken);
        await _storage.write(key: 'refresh_token', value: newRefreshToken);

        print(' Token renovado exitosamente.');
      } else {
        print(' Error al renovar el token: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error en _refreshAccessToken: $e');
    }
  }

  Future<void> _fetchUserIdByEmail(String email) async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) {
        print('Error: No se encontró el token de autenticación.');
        return;
      }

      final response = await http.post(
        Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/get-app-user-by-email'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['status'] == true && responseData['data'] != null) {
          final appUser = responseData['data']['app_user'];
          if (appUser != null && appUser['id'] != null) {
            String userId = appUser['id'].toString();
            await _storage.write(key: 'user_id', value: userId);
          } else {
            print('No se encontró el ID del usuario en la respuesta.');
          }
        } else {
          print('Error: Usuario no encontrado en la API.');
        }
      } else {
        print('Error en la solicitud de usuario: Código ${response.statusCode}, Respuesta: ${response.body}');
      }
    } catch (e) {
      print('Error al obtener el ID del usuario: $e');
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
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 100,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Bienvenid@ al Portal interno\n de IPS ChileAtiende',
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Si eres funcionari@ y quieres mantenerte informado\n'
                'sobre todo lo que está pasando en nuestra institución.',
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: isLoading
                    ? Container(
                        width: 320,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () async {
                          _launchAuthUrl();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 15),
                          minimumSize: const Size(250, 50),
                          fixedSize: const Size(320, 60),
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
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
