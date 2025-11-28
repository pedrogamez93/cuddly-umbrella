// lib/screens/notification_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/notification_item.dart';
import 'item_detail_screen.dart';

class NotificationDetailScreen extends StatefulWidget {
  const NotificationDetailScreen({super.key, required this.notification});

  final NotificationItem notification;

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  final _storage = const FlutterSecureStorage();
  bool _loadingOpen = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final hint = _guessTargetFromMessage(n.message);

    return Scaffold(
      appBar: AppBar(title: const Text('Notificación')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Título
          Text(
            n.title.isEmpty ? 'Notificación' : n.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),

          // Mensaje
          Text(n.message),
          const SizedBox(height: 12),

          // Fecha
          Text(
            'Recibida: ${_formatDateTime(n.timestamp)}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),

          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],

          // Acciones principales
          if (hint.id != null && hint.id!.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _loadingOpen ? null : () => _openPostById(hint.id!),
              icon: const Icon(Icons.article_outlined),
              label: Text(_loadingOpen ? 'Abriendo…' : 'Abrir noticia'),
            ),
          if (hint.url != null && hint.url!.startsWith('http')) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(hint.url!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.link),
              label: const Text('Abrir enlace'),
            ),
          ],

          if ((hint.id == null || hint.id!.isEmpty) &&
              (hint.url == null || !hint.url!.startsWith('http')))
            const Text(
              'Esta notificación no incluye un enlace ni un contenido para abrir.',
              style: TextStyle(color: Colors.black54),
            ),
        ],
      ),
    );
  }

  // --- Abrir por id de página ---
  Future<void> _openPostById(String id) async {
    setState(() {
      _loadingOpen = true;
      _error = null;
    });
    try {
      final token = await _storage.read(key: 'access_token');
      if (!mounted) return;
      if (token == null) {
        setState(() => _error = 'No hay sesión para abrir el contenido.');
        return;
      }

      final uri = Uri.parse(
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/news/get-page?page_id=$id',
      );
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      if (resp.statusCode == 200) {
        final jsonBody = json.decode(resp.body) as Map<String, dynamic>;
        final data = jsonBody['data'];
        if (data != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItemDetailScreen(itemData: Map<String, dynamic>.from(data)),
            ),
          );
        } else {
          setState(() => _error = 'No se encontró el contenido.');
        }
      } else {
        setState(() => _error = 'Error ${resp.statusCode} al cargar el contenido.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Fallo al abrir contenido: $e');
    } finally {
      if (mounted) setState(() => _loadingOpen = false);
    }
  }

  // --- Heurística: deduce id y/o url desde el mensaje ---
  _TargetHint _guessTargetFromMessage(String rawMsg) {
    String msg = rawMsg.trim();
    String? id;
    String? url;

    // 1) JSON completo o embebido en el texto
    Map<String, dynamic>? parsed;
    try {
      if (msg.startsWith('{') && msg.endsWith('}')) {
        parsed = json.decode(msg);
      } else {
        final start = msg.indexOf('{');
        final end = msg.lastIndexOf('}');
        if (start >= 0 && end > start) {
          parsed = json.decode(msg.substring(start, end + 1));
        }
      }
    } catch (_) {}
    if (parsed != null) {
      id  ??= parsed['page_id']?.toString() ??
              parsed['post_id']?.toString() ??
              parsed['id']?.toString();
      url ??= parsed['url']?.toString();
    }

    // 2) URL suelta en el texto
    final mUrl = RegExp('https?:\\/\\/[^\\s)\'"<>]+').firstMatch(msg);
    if (mUrl != null) url ??= mUrl.group(0);

    // 3) page_id=123 / post_id=123 / id: 123
    final mId = RegExp(
      r'(?:page_id|post_id|id)\s*[:=]\s*([0-9]+)',
      caseSensitive: false,
    ).firstMatch(msg);
    if (mId != null) id ??= mId.group(1);

    return _TargetHint(id: id, url: url);
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
    // Si prefieres relativo, reemplaza por un helper tipo "hace 2 h".
  }
}

class _TargetHint {
  final String? id;
  final String? url;
  _TargetHint({this.id, this.url});
}
