import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSyncWS {
  AppSyncWS({
    required this.wssUrl,
    required this.host,
    required this.apiKey, // ⚠️ solo QA; en prod usa JWT/IAM
    this.onNotification,
  });

  final String wssUrl; // wss://notificaciones-somos-wss.qa.chileatiende.cl/graphql/realtime
  final String host;   // avnaqxexqvabxdndyro3w42zfi.appsync-api.us-east-1.amazonaws.com
  final String apiKey; // da2-xxxxx (QA)
  final void Function(Map<String, dynamic>)? onNotification;

  WebSocket? _ws;
  Timer? _kaTimer;
  String? _subId;
  String? _lastEmail;
  final _storage = const FlutterSecureStorage();

  bool get isOpen => _ws != null && _ws!.readyState == WebSocket.open;

  Future<void> connectAndSubscribe({String? userEmail}) async {
    final email = (userEmail ?? await _storage.read(key: 'user_email'))?.trim();
    if (email == null || email.isEmpty) {
      throw Exception('No se encontró USER_EMAIL del usuario logueado.');
    }
    _lastEmail = email;

    await _open();
    await _connectionInit();
    await _startSubscription(userEmail: email);
  }

  Future<void> _open() async {
    final headers = {'host': host, 'x-api-key': apiKey};
    final enc = base64Url.encode(utf8.encode(jsonEncode(headers))).replaceAll('=', '');
    _ws = await WebSocket.connect(
      wssUrl,
      protocols: ['header-$enc', 'graphql-ws'],
    );
    _ws!.listen(_onMessage, onError: _onError, onDone: _onDone);
  }

  Future<void> _connectionInit() async {
    final payload = {'host': host, 'x-api-key': apiKey};
    _ws!.add(jsonEncode({'type': 'connection_init', 'payload': payload}));
  }

  Future<void> _startSubscription({required String userEmail}) async {
    if (!isOpen) return;
    _subId = DateTime.now().millisecondsSinceEpoch.toString();

    const query = r'''
      subscription OnNewNotification($userEmail: String!) {
        onNewNotification(userEmail: $userEmail) {
          id title message timestamp viewed viewedAt deleted deletedAt
          targetType targetId targetUrl
        }
      }
    ''';

    final payload = {
      'data': jsonEncode({
        'query': query,
        'variables': {'userEmail': userEmail},
      }),
      'extensions': {
        'authorization': {'host': host, 'x-api-key': apiKey}
      }
    };

    _ws!.add(jsonEncode({'id': _subId, 'type': 'start', 'payload': payload}));
  }

  void _onMessage(dynamic data) {
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'connection_ack':
      case 'ka':
        _armKeepAlive();
        break;
      case 'data':
        final payload = msg['payload'] as Map<String, dynamic>?;
        final root = payload?['data'] as Map<String, dynamic>?;
        final notif = root?['onNewNotification'] as Map<String, dynamic>?;
        if (notif != null) onNotification?.call(notif);
        break;
      case 'error':
        // ignore: avoid_print
        print('GraphQL error: ${msg['payload']}');
        break;
      case 'complete':
        break;
    }
  }

  void _armKeepAlive() {
    _kaTimer?.cancel();
    _kaTimer = Timer(const Duration(seconds: 90), _reconnect);
  }

  void _onError(Object e) {
    // ignore: avoid_print
    print('WS error: $e');
    _reconnect();
  }

  void _onDone() => _reconnect();

  Future<void> _reconnect() async {
    _kaTimer?.cancel();
    try { await _ws?.close(); } catch (_) {}
    _ws = null;
    await Future.delayed(const Duration(seconds: 2));

    if (_lastEmail != null && _lastEmail!.isNotEmpty) {
      try {
        await _open();
        await _connectionInit();
        await _startSubscription(userEmail: _lastEmail!);
      } catch (e) {
        // ignore: avoid_print
        print('Reintento WS falló: $e');
      }
    }
  }

  Future<void> dispose() async {
    _kaTimer?.cancel();
    if (isOpen && _subId != null) {
      _ws!.add(jsonEncode({'id': _subId, 'type': 'stop'}));
    }
    await _ws?.close();
    _ws = null;
  }
}
