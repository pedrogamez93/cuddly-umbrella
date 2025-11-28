// lib/screens/posts_search_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'single_post_screen.dart';

const _storage = FlutterSecureStorage();

class PostsSearchScreen extends StatefulWidget {
  const PostsSearchScreen({super.key});

  @override
  State<PostsSearchScreen> createState() => _PostsSearchScreenState();
}

class _PostsSearchScreenState extends State<PostsSearchScreen> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _error = false;
  bool _hasMore = true;

  int _page = 1;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 300) {
      if (!_loading && _hasMore && _query.isNotEmpty) {
        _fetch();
      }
    }
  }

  Future<void> _startSearch(String q) async {
    final query = q.trim();
    setState(() {
      _query = query;
      _page = 1;
      _results.clear();
      _hasMore = true;
      _error = false;
    });
    if (query.isNotEmpty) {
      await _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) {
        throw Exception('Sin token de autenticación');
      }

      final uri = Uri.parse(
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/posts/search'
        '?query=${Uri.encodeQueryComponent(_query)}&page=$_page&per_page=18',
      );

      debugPrint('➡️ GET $uri');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      debugPrint('⬅️ ${res.statusCode}');
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final items = (data['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final int current = (data['current_page'] ?? _page) as int;
      final int last = (data['last_page'] ?? current) as int;

      setState(() {
        _results.addAll(items);
        _page = current + 1;
        _hasMore = current < last;
        _error = false;
      });
    } catch (e) {
      debugPrint('Search error: $e');
      setState(() => _error = true);
    } finally {
      setState(() => _loading = false);
    }
  }

  // ---------- Helpers para imágenes / normalización ----------

  String? _normalizeUrl(dynamic u) {
    if (u == null) return null;
    var s = u.toString().trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(r'\/', '/').replaceAll('\\/', '/').replaceAll('\\', '');
    if (s.startsWith('https:/') && !s.startsWith('https://')) {
      s = s.replaceFirst('https:/', 'https://');
    }
    if (s.startsWith('http:/') && !s.startsWith('http://')) {
      s = s.replaceFirst('http:/', 'http://');
    }
    return s;
  }

  // Extrae TODAS las URLs de imágenes que encuentre en posibles campos
  List<String> _allImagesFromPost(Map<String, dynamic> post) {
    final set = <String>{};

    // Claves directas comunes
    for (final key in ['image', 'image_url', 'cover_url', 'thumbnail_url']) {
      final u = _normalizeUrl(post[key]);
      if (u != null && _looksLikeImage(u)) set.add(u);
    }

    // Si ya viene 'images' (lista), las añadimos
    if (post['images'] is List) {
      for (final it in (post['images'] as List)) {
        final u = _normalizeUrl(it);
        if (u != null && _looksLikeImage(u)) set.add(u);
      }
    }

    // Explora campos largos de texto donde suelen venir URLs
    for (final key in ['content', 'summary', 'body', 'description']) {
      final v = post[key];
      if (v is! String || v.isEmpty) continue;

      // a) <img src="...">
      final rxImg = RegExp(
        r'''<img\s[^>]*src=["']([^"']+)["']''',
        caseSensitive: false,
      );
      for (final m in rxImg.allMatches(v)) {
        final u = _normalizeUrl(m.group(1));
        if (u != null && _looksLikeImage(u)) set.add(u);
      }

      // b) URLs directas a imágenes dentro del texto/DSL
      final rxUrl = RegExp(
        r'''(https?:\/\/[^\s"')]+?\.(?:png|jpe?g|gif|webp|svg)(?:\?[^\s"']*)?)''',
        caseSensitive: false,
      );
      for (final m in rxUrl.allMatches(v)) {
        final u = _normalizeUrl(m.group(1));
        if (u != null && _looksLikeImage(u)) set.add(u);
      }
    }

    return set.toList();
  }

  bool _looksLikeImage(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.svg') ||
        lower.contains('.png?') ||
        lower.contains('.jpg?') ||
        lower.contains('.jpeg?') ||
        lower.contains('.gif?') ||
        lower.contains('.webp?') ||
        lower.contains('.svg?');
  }

  // Usa para miniatura en la grilla
  String? _pickImageUrl(Map<String, dynamic> post) {
    final all = _allImagesFromPost(post);
    if (all.isNotEmpty) return all.first;
    return null;
  }

  InlineSpan _buildHighlightSpan(String raw) {
    final parts = raw.split(RegExp(r'(<em>|</em>)'));
    bool inEm = false;
    return TextSpan(
      children: parts.map((p) {
        if (p == '<em>') {
          inEm = true;
          return const TextSpan(text: '');
        }
        if (p == '</em>') {
          inEm = false;
          return const TextSpan(text: '');
        }
        return TextSpan(
          text: p,
          style: inEm ? const TextStyle(fontWeight: FontWeight.w700) : null,
        );
      }).toList(),
    );
  }

  Map<String, dynamic> _preparePostForDetail(Map<String, dynamic> post) {
    final images = _allImagesFromPost(post);
    return {
      ...post,
      if (images.isNotEmpty) 'images': images,
    };
  }

  void _openDetail(Map<String, dynamic> post) {
    final prepared = _preparePostForDetail(post);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SinglePostScreen(post: prepared),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSearch = _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: _startSearch,
            decoration: InputDecoration(
              hintText: 'Buscar posts...',
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF2F4F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.arrow_forward),
            onPressed: canSearch ? () => _startSearch(_controller.text) : null,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_query.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Escribe algo para buscar en posts.'),
            ),
          if (_error)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No se pudo buscar. Inténtalo de nuevo.'),
            ),
          Expanded(
            child: _results.isEmpty
                ? (_loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_query.isNotEmpty && !_error
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                'No se encontraron resultados para esta búsqueda.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink()))
                : GridView.builder(
                    controller: _scrollCtrl,
                    // 👉 sin padding para que se vea pegado
                    padding: EdgeInsets.zero,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, // estilo explore
                      mainAxisSpacing: 1, // 👉 gutters finos tipo IG
                      crossAxisSpacing: 1, // 👉 gutters finos tipo IG
                      childAspectRatio: 1,
                    ),
                    itemCount: _results.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _results.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final post = _results[index];
                      final image = _pickImageUrl(post);
                      final String title = (post['title'] ?? '').toString();

                      return GestureDetector(
                        onTap: () => _openDetail(post),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (image != null)
                              InkWell(
                                onTap: () => _openDetail(post),
                                child: Image.network(
                                  image,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              InkWell(
                                onTap: () => _openDetail(post),
                                child: Container(
                                  color: const Color(0xFFE9EDF2),
                                  alignment: Alignment.bottomLeft,
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),

                            // faja inferior (opcional; muy sutil para no “recortar” el borde)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Colors.black45, Colors.transparent],
                                  ),
                                ),
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
