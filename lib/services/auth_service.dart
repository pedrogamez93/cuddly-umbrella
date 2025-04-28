import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class AuthService {
  final _storage = FlutterSecureStorage();
  final String clientId = '9'; 
  final String redirectUri = 'http://localhost:3000/login/callback';
  final String authUrl = 'https://auth.test.chileatiende.gob.cl/oauth/authorize';
  final String tokenUrl = 'https://auth.test.chileatiende.gob.cl/oauth/token';

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
  
  Future<void> storeStateAndVerifier(String state, String verifier) async {
    await _storage.write(key: 'state', value: state);
    await _storage.write(key: 'verifier', value: verifier);
  }

  String buildAuthUrl(String state, String challenge) {
    return '$authUrl?client_id=$clientId&redirect_uri=$redirectUri'
           '&response_type=code&scope=*&state=$state'
           '&code_challenge=$challenge&code_challenge_method=S256';
  }

  Future<void> launchAuthUrl(String authUrl) async {
    final Uri url = Uri.parse(authUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $authUrl';
    }
  }
  
  Future<void> exchangeCodeForToken(String code) async {
    final verifier = await _storage.read(key: 'verifier');

    final response = await http.post(
      Uri.parse(tokenUrl),
      body: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
      },
    );

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      final accessToken = responseData['access_token'];
      final refreshToken = responseData['refresh_token'];
      await _storage.write(key: 'access_token', value: accessToken);
      await _storage.write(key: 'refresh_token', value: refreshToken);
    } else {
      throw Exception('Failed to exchange token');
    }
  }
}
