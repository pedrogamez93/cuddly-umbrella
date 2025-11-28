// lib/widgets/share_content_sheet.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ShareContentSheet extends StatefulWidget {
  /// 'post' | 'story'
  final String type;

  /// ID del post o historia
  final String contentId;

  /// Sugerencia inicial (opcional)
  final String? initialTitle;

  /// Sugerencia inicial (opcional)
  final String? initialMessage;

  const ShareContentSheet({
    super.key,
    required this.type,
    required this.contentId,
    this.initialTitle,
    this.initialMessage,
  });

  @override
  State<ShareContentSheet> createState() => _ShareContentSheetState();
}

class _ShareContentSheetState extends State<ShareContentSheet> {
  // ===== API =====
  static const _host = 'somos-api-cms.qa.chileatiende.cl';
  static const _pathUsers = '/api/mobile-app/get-share-users';
  static const _pathShare = '/api/mobile-app/share-content';

  final _storage = const FlutterSecureStorage();

  // ===== UI state =====
  final _searchCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _manualEmailCtrl = TextEditingController();

  final _usersScrollCtrl = ScrollController();

  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  String? _error;

  final Set<String> _selectedEmails = {}; // correos únicos
  bool _sending = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.initialTitle?.trim() ?? '';
    _messageCtrl.text = widget.initialMessage?.trim() ?? '';
    _fetchUsers(search: '');
    _usersScrollCtrl.addListener(_onUsersScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _usersScrollCtrl.dispose();
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    _manualEmailCtrl.dispose();
    super.dispose();
  }

  void _onUsersScroll() {
    // Si luego se pagina, aquí se puede disparar la próxima página
  }

  // ========================= GET USERS =========================
  Future<void> _fetchUsers({required String search}) async {
    setState(() {
      _loading = true;
      _error = null;
      _users = [];
    });

    final token = await _storage.read(key: 'access_token');
    final appUserId =
        await _storage.read(key: 'app_user_id') ?? await _storage.read(key: 'user_id');

    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No hay sesión (token).';
      });
      return;
    }
    if (appUserId == null || appUserId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Falta app_user_id. Guárdalo al iniciar sesión.';
      });
      return;
    }

    // Igual que tu Postman: app_user_id, per_page=10, page=1, search=...
    final params = <String, String>{
      'app_user_id': appUserId,
      'per_page': '10',
      'page': '1',
      if (search.trim().isNotEmpty) 'search': search.trim(),
    };

    final uri = Uri.https(_host, _pathUsers, params);
    debugPrint('[share-users] ▶ GET $uri');

    try {
      final r = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      debugPrint('[share-users] ◀ ${r.statusCode} bodylen=${r.body.length}');
      if (r.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'HTTP ${r.statusCode}: ${r.body}';
        });
        return;
      }

      final root = json.decode(r.body);

      // Soporta { data:[..] } o { data:{ data:[..] } }
      final List list =
          (root is Map && root['data'] is List)
              ? root['data']
              : (root is Map && root['data'] is Map && root['data']['data'] is List)
                  ? root['data']['data']
                  : const [];

      // Filtra usuarios sin email
      final clean = list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((m) => (m['email'] ?? '').toString().trim().isNotEmpty)
          .toList();

      setState(() {
        _users = clean;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error de red: $e';
      });
    }
  }

  // ========================= POST SHARE =========================
  Future<void> _submit() async {
    final token = await _storage.read(key: 'access_token');
    final appUserId =
        await _storage.read(key: 'app_user_id') ?? await _storage.read(key: 'user_id');

    if (token == null || token.isEmpty) {
      _snack('No hay sesión (token).');
      return;
    }
    if (appUserId == null || appUserId.isEmpty) {
      _snack('Falta app_user_id.');
      return;
    }
    if (_selectedEmails.isEmpty) {
      _snack('Selecciona al menos un correo.');
      return;
    }

    setState(() => _sending = true);

    final int? contentIdInt = int.tryParse(widget.contentId);
    final int? appUserIdInt = int.tryParse(appUserId);

    final body = <String, dynamic>{
      'app_user_id': appUserIdInt ?? appUserId,
      'type': widget.type, // 'post' o 'story'
      'content_id': contentIdInt ?? widget.contentId,
      'distribution_list_id': 'manual',
      'user_emails': _selectedEmails.toList(),
      if (_titleCtrl.text.trim().isNotEmpty) 'title': _titleCtrl.text.trim(),
      if (_messageCtrl.text.trim().isNotEmpty) 'message': _messageCtrl.text.trim(),
    };

    final uri = Uri.https(_host, _pathShare);
    debugPrint('[share] ▶ POST $uri body=${json.encode(body)}');

    try {
      final r = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );
      debugPrint('[share] ◀ ${r.statusCode} ${r.body}');
      if (r.statusCode == 200 || r.statusCode == 201) {
        // algunos backend devuelven {status:true} u OK 200.
        _snack('Contenido compartido.');
        if (mounted) Navigator.of(context).pop(true);
      } else {
        _snack('No se pudo compartir (HTTP ${r.statusCode}).');
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ========================= helpers =========================
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _displayNameOf(Map<String, dynamic> u) {
    final fullName = (u['full_name'] ?? '').toString().trim();
    if (fullName.isNotEmpty) return fullName;
    final names = (u['names'] ?? '').toString().trim();
    final surnames = (u['surnames'] ?? '').toString().trim();
    final joined = [names, surnames].where((s) => s.isNotEmpty).join(' ');
    if (joined.isNotEmpty) return joined;
    final username = (u['username'] ?? '').toString().trim();
    if (username.isNotEmpty) return username;
    return (u['email'] ?? '').toString().trim();
  }

  bool _isValidEmail(String s) {
    final rx = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return rx.hasMatch(s.trim());
  }

  void _debouncedSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchUsers(search: value);
    });
  }

  // ========================= UI =========================
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              const SizedBox(height: 6),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      'Compartir ${widget.type == 'story' ? 'historia' : 'post'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _sending ? null : () => Navigator.of(context).maybePop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),

              // Buscar usuarios
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _debouncedSearch,
                        onSubmitted: (v) => _fetchUsers(search: v),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Buscar usuarios…',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Buscar',
                      onPressed: () => _fetchUsers(search: _searchCtrl.text),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),

              // Lista de usuarios
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(_error!, textAlign: TextAlign.center),
                            ),
                          )
                        : _users.isEmpty
                            ? const Center(
                                child: Text(
                                  'Sin resultados.\nPrueba con otro texto de búsqueda.',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.separated(
                                controller: _usersScrollCtrl,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: _users.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final u = _users[i];
                                  final email = (u['email'] ?? '').toString().trim();
                                  final pic = (u['profile_picture_url'] ?? '').toString().trim();
                                  final selected = _selectedEmails.contains(email);

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.grey[200],
                                      backgroundImage:
                                          pic.isNotEmpty ? NetworkImage(pic) : null,
                                      child: pic.isEmpty
                                          ? const Icon(Icons.person, color: Colors.grey)
                                          : null,
                                    ),
                                    title: Text(_displayNameOf(u)),
                                    subtitle: Text(email),
                                    trailing: Checkbox(
                                      value: selected,
                                      onChanged: (_) {
                                        setState(() {
                                          if (selected) {
                                            _selectedEmails.remove(email);
                                          } else {
                                            _selectedEmails.add(email);
                                          }
                                        });
                                      },
                                    ),
                                    onTap: () {
                                      setState(() {
                                        if (selected) {
                                          _selectedEmails.remove(email);
                                        } else {
                                          _selectedEmails.add(email);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
              ),

              // Correos seleccionados (chips)
              if (_selectedEmails.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: -6,
                    children: _selectedEmails
                        .map((e) => Chip(
                              label: Text(e),
                              onDeleted: () {
                                setState(() => _selectedEmails.remove(e));
                              },
                            ))
                        .toList(),
                  ),
                ),

            

              // Título y Mensaje
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _titleCtrl,
                  maxLength: 150,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Título (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _messageCtrl,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Mensaje (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // Botón enviar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_sending ? 'Enviando…' : 'Enviar'),
                    onPressed: _sending ? null : _submit,
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
