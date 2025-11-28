// lib/screens/profile_screen.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'single_post_screen.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = const FlutterSecureStorage();

  String? profileImage; // profile_picture_url
  String? fullname = 'Cargando...';
  String? email = 'Cargando...';
  String? officeLocation = 'Cargando...';

  /// Máximo 9 ítems por sección
  List<Map<String, dynamic>> likedPosts = [];
  List<Map<String, dynamic>> commentedPosts = [];

  bool isLoading = true;

  final Map<String, Future<Uint8List?>> _imageFutures = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // -------------------- Carga de perfil + secciones --------------------
  Future<void> _loadUserData() async {
    try {
      // 0) Prefill: Storage / JWT (para no mostrar “Cargando...”)
      await _prefillFromStorageAndJwt();

      final storedUserId = await _storage.read(key: 'user_id');
      final bearerUser = await _readBearerUser();

      // officeLocation desde JWT (si existe)
      if (bearerUser != null) {
        final decodedOffice = _decodeOfficeLocationFromAccessToken(bearerUser);
        if (decodedOffice != null) {
          setState(() => officeLocation = decodedOffice);
        }
      }

      if (storedUserId == null || bearerUser == null) {
        debugPrint('[ProfileScreen] Faltan credenciales para cargar perfil');
        if (mounted) setState(() => isLoading = false);
        return;
      }

      // 1) PERFIL (sobre-escribe el prefill si responde)
      await _fetchUserProfile(int.parse(storedUserId), bearerUser);

      // 2) Comentarios recientes (máx 9)
      await _fetchRecentCommentedPosts(
        userId: int.parse(storedUserId),
        bearer: bearerUser,
        maxItems: 9,
      );

      // 3) Likes recientes (máx 9)
      await _fetchLikedPosts(
        userId: int.parse(storedUserId),
        bearer: bearerUser,
        maxItems: 9,
      );
    } catch (e, st) {
      debugPrint('[ProfileScreen] _loadUserData ERROR: $e\n$st');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Prefill: toma nombre/correo desde SecureStorage y/o JWT para no
  /// dejar el UI en “Cargando...”
  Future<void> _prefillFromStorageAndJwt() async {
    String? name = await _storage.read(key: 'user_full_name');
    String? mail = await _storage.read(key: 'user_email');

    // Si no hay en storage, intenta desde JWT
    if (mail == null || mail.trim().isEmpty || (name == null || name.trim().isEmpty)) {
      final jwt = await _storage.read(key: 'auth_token') ??
          await _storage.read(key: 'access_token');
      if (jwt != null && jwt.isNotEmpty) {
        final claims = _decodeJwt(jwt);
        mail ??= (claims['email'] ?? claims['user_email'] ?? claims['upn'])?.toString();
        name ??= (claims['name'] ?? claims['given_name'])?.toString();
      }
    }

    setState(() {
      if (name != null && name.trim().isNotEmpty) {
        fullname = name.trim();
      }
      if (mail != null && mail.trim().isNotEmpty) {
        email = mail.trim();
      }
    });
  }

  /// token Authorization: Bearer ...
  Future<String?> _readBearerUser() async {
    return await _storage.read(key: 'BEARER_USER') ??
        await _storage.read(key: 'bearer_user') ??
        await _storage.read(key: 'access_token');
  }

  // -------------------- Perfil --------------------
  Future<void> _fetchUserProfile(int userId, String bearerUser) async {
    const endpoint =
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/get-app-user';

    try {
      final resp = await http.post(
        Uri.parse(endpoint),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        }..addAll({'Authorization': 'Bearer $bearerUser'}),
        body: {'app_user_id': userId.toString()},
      );

      if (resp.statusCode != 200) {
        debugPrint('[ProfileScreen] get-app-user HTTP ${resp.statusCode}: ${resp.body}');
        return;
      }

      final jsonBody = json.decode(resp.body) as Map<String, dynamic>;
      final appUser = (jsonBody['data']?['app_user']) as Map<String, dynamic>?;
      if (appUser == null) return;

      final full = (appUser['full_name'] ?? '').toString().trim();
      final mail = (appUser['email'] ?? '').toString().trim();
      String? avatar = appUser['profile_picture_url']?.toString();
      if (avatar != null && avatar.isNotEmpty) {
        avatar = Uri.encodeFull(avatar.replaceAll(r'\', '').trim());
      }

      setState(() {
        if (full.isNotEmpty) fullname = full;
        if (mail.isNotEmpty) email = mail;
        profileImage = avatar; // puede ser null
      });
    } catch (e, st) {
      debugPrint('[ProfileScreen] get-app-user ERROR: $e\n$st');
    }
  }

  // -------------------- Comentarios recientes (máx 9) --------------------
  Future<void> _fetchRecentCommentedPosts({
    required int userId,
    required String bearer,
    int maxItems = 9,
  }) async {
    final url =
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/get-user-comments'
        '?page=1&per_page=$maxItems&app_user_id=$userId';

    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $bearer', 'Accept': 'application/json'},
      );

      if (resp.statusCode != 200) {
        debugPrint('[ProfileScreen] get-user-comments HTTP ${resp.statusCode}: ${resp.body}');
        setState(() => commentedPosts = []);
        return;
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      final list = (body['data'] as List?) ?? const [];
      final Set<int> uniquePostIds = {};

      for (final row in list) {
        final oc = row['original_content'] as Map<String, dynamic>?;
        if (oc == null) continue;
        if ((oc['type'] ?? '').toString().toLowerCase() != 'post') continue;
        final data = oc['data'] as Map<String, dynamic>?;
        final pid = int.tryParse('${data?['id']}');
        if (pid != null) uniquePostIds.add(pid);
        if (uniquePostIds.length >= maxItems) break;
      }

      final results = <Map<String, dynamic>>[];
      for (final pid in uniquePostIds) {
        final row = list.firstWhere(
          (e) => (e['original_content']?['data']?['id']).toString() == pid.toString(),
          orElse: () => null,
        );
        final mapped = _mapPostFromOriginalContent(
          (row?['original_content']?['data']) as Map<String, dynamic>?,
        );
        if (mapped != null) results.add(mapped);
      }

      setState(() => commentedPosts = results.take(maxItems).toList());
    } catch (e, st) {
      debugPrint('[ProfileScreen] get-user-comments ERROR: $e\n$st');
      setState(() => commentedPosts = []);
    }
  }

  // -------------------- Likes recientes (máx 9) --------------------
  Future<void> _fetchLikedPosts({
    required int userId,
    required String bearer,
    int maxItems = 9,
  }) async {
    final url =
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-posts-app-user'
        '?app_user_id=$userId&page=1';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $bearer', 'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        debugPrint('[ProfileScreen] like-posts-app-user HTTP ${response.statusCode}');
        setState(() => likedPosts = []);
        return;
      }

      final data = json.decode(response.body);
      final arr = (data['data'] as List?) ?? const [];

      final List<Map<String, dynamic>> mapped = [];
      for (var post in arr) {
        try {
          mapped.add(_mapPostFromListItem(Map<String, dynamic>.from(post)));
        } catch (e) {
          debugPrint('[ProfileScreen] parse liked post error: $e');
        }
        if (mapped.length >= maxItems) break;
      }

      setState(() => likedPosts = mapped);
    } catch (e) {
      debugPrint('[ProfileScreen] like-posts-app-user ERROR: $e');
      setState(() => likedPosts = []);
    }
  }

  // -------------------- Mapear posts a nuestro formato --------------------
  Map<String, dynamic>? _mapPostFromOriginalContent(Map<String, dynamic>? post) {
    if (post == null) return null;
    final metaKeyRaw = post['meta_key']?.toString();
    final images = _extractImagesFromMeta(metaKeyRaw);
    final content = _firstParagraphFromMeta(metaKeyRaw);
    return {
      'id': post['id'],
      'title': post['title'],
      'image': images.isNotEmpty ? images.first : '',
      'images': images,
      'content': content ?? 'Sin contenido disponible',
      'likes': post['likes_count'],
      'comments': post['comments_count'],
      'published_at': post['published_at'],
      'meta_key': metaKeyRaw,
    };
  }

  Map<String, dynamic> _mapPostFromListItem(Map<String, dynamic> post) {
    final metaKeyRaw = post['meta_key']?.toString();
    final images = _extractImagesFromMeta(metaKeyRaw);
    final content = _firstParagraphFromMeta(metaKeyRaw);
    return {
      'id': post['id'],
      'title': post['title'],
      'image': images.isNotEmpty ? images.first : '',
      'images': images,
      'content': content ?? 'Sin contenido disponible',
      'likes': post['likes_count'],
      'comments': post['comments_count'],
      'published_at': post['published_at'],
      'meta_key': metaKeyRaw,
    };
  }

  List<String> _extractImagesFromMeta(String? metaKeyRaw) {
    if (metaKeyRaw == null || metaKeyRaw.isEmpty) return const [];
    List<dynamic>? metaList;
    try {
      metaList = json.decode(metaKeyRaw) as List<dynamic>;
    } catch (_) {
      try {
        metaList =
            json.decode(metaKeyRaw.replaceAll(r'\\', r'\\\\').replaceAll(r'\/', '/')) as List<dynamic>;
      } catch (_) {}
    }
    if (metaList == null) return const [];

    for (final item in metaList) {
      if (item is Map && item['type'] == 'image-carousel' && item['cards'] is List) {
        final list = (item['cards'] as List)
            .map((e) => (e['image'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .map((s) => Uri.encodeFull(s.replaceAll(r'\\', '').replaceAll(r'\/', '/')))
            .toList();
        if (list.isNotEmpty) return list;
      }
    }
    for (final item in metaList) {
      if (item is Map && item['type'] == 'image' && (item['image'] ?? '').toString().isNotEmpty) {
        final s = (item['image'] as String).replaceAll(r'\\', '').replaceAll(r'\/', '/');
        return [Uri.encodeFull(s)];
      }
    }
    return const [];
  }

  String? _firstParagraphFromMeta(String? metaKeyRaw) {
    if (metaKeyRaw == null || metaKeyRaw.isEmpty) return null;
    try {
      final list = json.decode(metaKeyRaw) as List<dynamic>;
      for (final item in list) {
        if (item is Map && item['type'] == 'paragraph' && item['paragraph-text'] != null) {
          return item['paragraph-text'].toString();
        }
      }
    } catch (_) {}
    return null;
  }

  // -------------------- Utilidades de imagen --------------------
  Future<Uint8List?> fetchImageBytes(String imageUrl) async {
    try {
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115 Safari/537.36',
          'Referer': 'https://chileatiende.gob.cl',
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        },
      );
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (e) {
      debugPrint('[ProfileScreen] fetchImageBytes error: $e');
      return null;
    }
  }

  Future<Uint8List?> _getImageFuture(String url) =>
      _imageFutures.putIfAbsent(url, () => fetchImageBytes(url));

  Widget _buildGridImage(String url) => FutureBuilder<Uint8List?>(
        future: _getImageFuture(url),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData) {
            return Container(
              color: Colors.black12,
              child: const Center(
                child: Icon(Icons.image_not_supported_outlined, color: Colors.black45),
              ),
            );
          }
          return Image.memory(snap.data!, fit: BoxFit.cover);
        },
      );

  // -------------------- Avatar --------------------
  Widget _buildAvatar() {
    // Evitar que “Cargando...” genere inicial C
    final nameForInitials =
        (fullname != null && !fullname!.toLowerCase().startsWith('cargando'))
            ? fullname!
            : 'Usuario';
    final initials = _initialsFromName(nameForInitials);

    if (profileImage == null || profileImage!.isEmpty) {
      return CircleAvatar(
        radius: 50,
        backgroundColor: Colors.blueGrey.shade100,
        child: Text(initials, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _getImageFuture(profileImage!),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const CircleAvatar(
            radius: 50,
            backgroundColor: Colors.black12,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        if (!snap.hasData) {
          return CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blueGrey.shade100,
            child: Text(initials, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          );
        }
        return CircleAvatar(radius: 50, backgroundImage: MemoryImage(snap.data!));
      },
    );
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'U';
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    final inits = (first + last).toUpperCase();
    return inits.isEmpty ? 'U' : inits;
  }

  // -------------------- JWT helpers --------------------
  Map<String, dynamic> _decodeJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return {};
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      return json.decode(payload) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String? _decodeOfficeLocationFromAccessToken(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) return null;
      final normalizedPayload = base64Url.normalize(parts[1]);
      final decodedPayload = utf8.decode(base64Url.decode(normalizedPayload));
      final payloadMap = json.decode(decodedPayload);

      final String? jwtCu = payloadMap['jwt_cu'];
      if (jwtCu == null) return null;

      final partsCU = jwtCu.split('.');
      if (partsCU.length != 3) return null;
      final normalizedPayloadCU = base64Url.normalize(partsCU[1]);
      final decodedPayloadCU = utf8.decode(base64Url.decode(normalizedPayloadCU));
      final payloadMapCU = json.decode(decodedPayloadCU);

      return payloadMapCU['officeLocation'];
    } catch (_) {
      return null;
    }
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildAvatar(),
                  const SizedBox(height: 16),
                  Text(fullname ?? 'Sin nombre',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(email ?? 'Sin correo', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(officeLocation ?? 'No disponible',
                      style: const TextStyle(fontSize: 14, color: Colors.black54)),
                  const SizedBox(height: 24),

                  Row(
                    children: const [
                      Icon(Icons.mode_comment_outlined),
                      SizedBox(width: 8),
                      Text('Mis comentarios',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Mis comentarios (máx 9)
          if (commentedPosts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('No has comentado recientemente.',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = commentedPosts[index];
                    final img = (post['image'] ?? '').toString();
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => SinglePostScreen(post: post))),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: img.isEmpty
                            ? Container(
                                color: Colors.black12,
                                child: const Center(
                                  child: Icon(Icons.image_outlined, color: Colors.black45),
                                ),
                              )
                            : _buildGridImage(img),
                      ),
                    );
                  },
                  childCount: commentedPosts.length.clamp(0, 9),
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Mis me gusta (máx 9)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  Icon(Icons.favorite, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Mis me gusta',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          if (likedPosts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('No tienes posts marcados con "Me gusta".',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = likedPosts[index];
                    final img = (post['image'] ?? '').toString();
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => SinglePostScreen(post: post))),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: img.isEmpty
                            ? Container(
                                color: Colors.black12,
                                child: const Center(
                                  child: Icon(Icons.image_outlined, color: Colors.black45),
                                ),
                              )
                            : _buildGridImage(img),
                      ),
                    );
                  },
                  childCount: likedPosts.length.clamp(0, 9),
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
