import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:uni_links/uni_links.dart' as ul;
import 'package:url_launcher/url_launcher.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ======== CONFIG SSO ========
  final String tokenUrl = 'https://auth.test.chileatiende.gob.cl/oauth/token';
  final String authorizeBase =
      'https://auth.test.chileatiende.gob.cl/oauth/authorize';
  final String clientId = '27';
  final String provider = 'azure';
  final String redirectUri = 'ipsapp://callback'; // móvil/escritorio (custom scheme)
  // Si en Web usas otro redirect (p.ej. https://tuapp.web/callback), léelo con Uri.base

  // ======== STORAGE ========
  // Nota: En Web, flutter_secure_storage_web usa localStorage (no cifrado).
  // Evita guardar tokens en Web; idealmente usa cookies HttpOnly desde el backend.
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // ======== PKCE ========
  String? _state;
  String? _verifier;
  String _challenge = '';

  // ======== CONTROL ========
  StreamSubscription? _linkSub;
  Timer? _refreshTimer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _setupLogin();         // Genera state/verifier/challenge y los guarda (no Web)
    _initDeepLinks();      // Maneja retorno SSO (Web vs móvil)
    _scheduleTokenRefresh();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ======== Helpers PKCE ========
  String _randomUrlSafe(int bytesLen, int outLen) {
    final rnd = Random.secure();
    final bytes = List<int>.generate(bytesLen, (_) => rnd.nextInt(256));
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    return b64.length >= outLen ? b64.substring(0, outLen) : b64;
  }

  Future<String> _codeChallengeS256(String verifier) async {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _setupLogin() async {
    try {
      // Genera valores nuevos para una sesión de login
      final newState = _randomUrlSafe(40, 40);
      final newVerifier = _randomUrlSafe(96, 128);
      final newChallenge = await _codeChallengeS256(newVerifier);

      _state = newState;
      _verifier = newVerifier;
      _challenge = newChallenge;

      // Guardar solo en plataformas seguras (no Web)
      if (!kIsWeb) {
        await _storage.write(key: 'state', value: _state);
        await _storage.write(key: 'verifier', value: _verifier);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error en _setupLogin: $e');
      }
    }
  }

  // ======== Deep Links / Retorno SSO ========
  Future<void> _initDeepLinks() async {
    if (kIsWeb) {
      // En Web NO usar streams (no están implementados). Lee Uri.base una sola vez.
      final uri = Uri.base;
      final code = uri.queryParameters['code'];
      final receivedState = uri.queryParameters['state'];
      if (code != null) {
        await _verifyAndExchangeCode(code: code, receivedState: receivedState);
      }
      return;
    }

    // Móvil/escritorio:
    try {
      // Link inicial (por si la app se abrió con un enlace)
      final initial = await ul.getInitialUri();
      if (!mounted) return;
      if (initial != null && initial.toString().startsWith(redirectUri)) {
        final code = initial.queryParameters['code'];
        final receivedState = initial.queryParameters['state'];
        if (code != null) {
          await _verifyAndExchangeCode(code: code, receivedState: receivedState);
        }
      }

      // Stream de enlaces subsecuentes
      _linkSub = ul.uriLinkStream.listen((Uri? uri) async {
        if (!mounted || uri == null) return;
        if (uri.toString().startsWith(redirectUri)) {
          final code = uri.queryParameters['code'];
          final receivedState = uri.queryParameters['state'];
          if (code != null) {
            await _verifyAndExchangeCode(code: code, receivedState: receivedState);
          }
        }
      }, onError: (err) {
        if (kDebugMode) debugPrint('uni_links error: $err');
      });
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('PlatformException uni_links: $e');
    } on FormatException catch (e) {
      if (kDebugMode) debugPrint('FormatException uni_links: $e');
    }
  }

  // ======== Intercambio code -> tokens ========
  Future<void> _verifyAndExchangeCode({
    required String code,
    String? receivedState,
  }) async {
    setState(() => _isLoading = true);

    try {
      String? storedState = _state;
      String? storedVerifier = _verifier;

      // En móvil podemos haber guardado en SecureStorage
      if (!kIsWeb) {
        storedState = storedState ?? await _storage.read(key: 'state');
        storedVerifier = storedVerifier ?? await _storage.read(key: 'verifier');
      }

      if (receivedState == null || storedState == null || receivedState != storedState) {
        if (kDebugMode) debugPrint('Estado inválido o ausente en retorno SSO.');
        return;
      }

      final params = {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code_verifier': storedVerifier ?? '',
        'code': code,
        'grant_type': 'authorization_code',
      };

      final resp = await http.post(
        Uri.parse(tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: params,
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;

        final accessToken = data['access_token'] as String?;
        final refreshToken = data['refresh_token'] as String?;


         final responseData = jsonDecode(resp.body);
          String accessToken1 = responseData['access_token'];

          await _storage.write(key: 'access_token', value: accessToken1);
          await _storage.write(key: 'refresh_token', value: responseData['refresh_token']);
            print('🔑 Token completo:');
            for (int i = 0; i < accessToken1.length; i += 100) {
              final endIdx = (i + 100 > accessToken1.length) ? accessToken1.length : i + 100;
              print(accessToken1.substring(i, endIdx));
            }


        if (accessToken == null || refreshToken == null) {
          if (kDebugMode) debugPrint('Respuesta sin tokens.');
          return;
        }

        // 🔎 Imprimir solo en debug web
        if (kIsWeb && kDebugMode) {
          debugPrint('🔑 Access Token: $accessToken');
          debugPrint('🔄 Refresh Token: $refreshToken');
        }

        if (!kIsWeb) {
          await _storage.write(key: 'access_token', value: accessToken);
          await _storage.write(key: 'refresh_token', value: refreshToken);
        }

        // Decodifica claims (sin loguear valores sensibles)
        final decoded = JwtDecoder.decode(accessToken);
        final userEmail = decoded['email']?.toString();
        final fullName = decoded['nombre_completo']?.toString();
        final photoUrl = decoded['photo']?.toString();

        if (!kIsWeb) {
          if (userEmail != null) {
            await _storage.write(key: 'user_email', value: userEmail);
          }
          if (fullName != null) {
            await _storage.write(key: 'user_full_name', value: fullName);
          }
          if (photoUrl != null) {
            await _storage.write(key: 'user_photo', value: photoUrl);
          }
        }

        if (userEmail != null) {
          await _fetchUserIdByEmail(userEmail);
        }

        // 🔒 Elimina materiales PKCE luego de usarlos
        if (!kIsWeb) {
          await _storage.delete(key: 'state');
          await _storage.delete(key: 'verifier');
        }
        _state = null;
        _verifier = null;
        _challenge = '';

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        if (kDebugMode) {
          debugPrint(
              'Error auth ${resp.statusCode}: ${resp.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error intercambio code->token: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  // ======== Renovación de tokens ========
  void _scheduleTokenRefresh() {
    // Revisa cada 15 min. Si faltan < 5 min, renueva.
    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      final expSoon = await _isTokenExpiringSoon();
      if (expSoon) {
        await _refreshAccessToken();
      }
    });
  }

  Future<bool> _isTokenExpiringSoon() async {
    if (kIsWeb) return false; // evita guardar/leer en Web

    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) return true;

    final expirationDate = JwtDecoder.getExpirationDate(accessToken);
    final remaining = expirationDate.difference(DateTime.now());
    return remaining.inMinutes < 5;
    // Alternativa robusta: usar 'expires_in' que devuelva el servidor y guardar timestamp.
  }

  Future<void> _refreshAccessToken() async {
    if (kIsWeb) return;

    try {
      final rToken = await _storage.read(key: 'refresh_token');
      if (rToken == null) {
        if (kDebugMode) debugPrint('No hay refresh_token; requiere login.');
        return;
      }

      final resp = await http.post(
        Uri.parse(tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': rToken,
        },
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final newAccess = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;

        if (newAccess != null) {
          await _storage.write(key: 'access_token', value: newAccess);
        }
        if (newRefresh != null) {
          await _storage.write(key: 'refresh_token', value: newRefresh);
        }
        if (kDebugMode) debugPrint('Token renovado.');
      } else {
        if (kDebugMode) {
          debugPrint('Refresh fallo ${resp.statusCode}: ${resp.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error en refresh: $e');
    }
  }

  // ======== API interna para obtener user_id por email ========
  Future<void> _fetchUserIdByEmail(String email) async {
    try {
      if (kIsWeb) return;

      final token = await _storage.read(key: 'access_token');
      if (token == null) {
        if (kDebugMode) debugPrint('Sin access_token para /get-app-user-by-email');
        return;
      }

      final resp = await http.post(
        Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/get-app-user-by-email'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email}),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['status'] == true && data['data'] != null) {
          final appUser = (data['data'] as Map<String, dynamic>)['app_user'] as Map<String, dynamic>?;
          final id = appUser?['id'];
          if (id != null) {
            await _storage.write(key: 'user_id', value: id.toString());
          }
        } else {
          if (kDebugMode) debugPrint('Usuario no encontrado en API.');
        }
      } else {
        if (kDebugMode) {
          debugPrint('Error get-user: ${resp.statusCode} ${resp.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error _fetchUserIdByEmail: $e');
    }
  }

  // ======== Lanzar flujo de autorización ========
  Future<void> _launchAuthUrl() async {
    // En Web puedes querer usar la URL pública como redirect (Uri.base.origin).
    final uri = Uri.parse(authorizeBase).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': '*',
      'state': _state ?? '',
      'code_challenge': _challenge,
      'code_challenge_method': 'S256',
      'provider': provider,
    });

    try {
      final ok = await canLaunchUrl(uri);
      if (ok) {
        // Para móviles, abre navegador/app externa
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (kDebugMode) debugPrint('No se pudo abrir URL de auth: $uri');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error al lanzar URL de auth: $e');
    }
  }

  // ======== UI ========
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Image.asset(
                  'assets/images/logo.png',
                  height: 100,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Bienvenid@ al Portal interno\nde IPS ChileAtiende',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Si eres funcionari@ y quieres mantenerte informad@\n'
                  'sobre todo lo que está pasando en nuestra institución.',
                  textAlign: TextAlign.left,
                  style: TextStyle(fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? Container(
                        width: 320,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    : SizedBox(
                        width: 320,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _launchAuthUrl,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
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
      ),
    );
  }
}
