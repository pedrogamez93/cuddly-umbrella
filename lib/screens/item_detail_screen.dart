import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../widgets/comments_sheet.dart';

final _storage = FlutterSecureStorage();

class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> itemData;
  const ItemDetailScreen({Key? key, required this.itemData}) : super(key: key);

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late Map<String, dynamic> itemData;

  String? title;
  String? publishedAt;
  int likesCount = 0;
  bool isLiked = false;
  bool isLoading = true;

  Widget? _thumbnailWidget;
  final List<Widget> _contentWidgets = [];

  /// Cada galería: {'title': String, 'slides': List<Map<String,String>>}
  /// slide: {'url': String, 'desc': String}
  final List<Map<String, dynamic>> _galleries = [];

  List<Map<String, dynamic>> _likesList = [];

  /// Cache de descargas por URL (lazy y memoizado)
  final Map<String, Future<Uint8List?>> _imageFutures = {};

  @override
  void initState() {
    super.initState();
    _loadItemDetails();
  }

  // -------------------- Comentarios --------------------
  void _openComments() async {
    final idStr = await _storage.read(key: 'user_id');
    if (!mounted) return;
    if (idStr == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debes iniciar sesión')));
      return;
    }
    final pageId = int.tryParse(itemData['id']?.toString() ?? '');
    if (pageId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: CommentsSheet(pageId: pageId),
      ),
    );
  }

  // -------------------- Red de imágenes --------------------
  Future<Uint8List?> _downloadImageAsBrowser(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: const {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
        'Referer': 'https://chileatiende.gob.cl',
        'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
      });
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (e) {
      // ignore: avoid_print
      print(' Excepción al descargar imagen: $e');
      return null;
    }
  }

  Future<Uint8List?> _getImageFuture(String url) =>
      _imageFutures.putIfAbsent(url, () => _downloadImageAsBrowser(url));

  /// Widget de imagen reutilizable.
  /// - Si [height] es null, la imagen calcula su altura (ideal para evitar bandas).
  /// - Si [expand] es true, el widget llenará el espacio disponible (útil en grillas).
  Widget _buildImageWidget(
    String url, {
    double? height, // null => la imagen define su altura
    double? width,
    BorderRadius? radius,
    String? heroTag,
    VoidCallback? onTap,
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    bool expand = false,
    Color? backgroundColor, // solo se usa cuando height != null
  }) {
    return FutureBuilder<Uint8List?>(
      future: _getImageFuture(url),
      builder: (context, snapshot) {
        Widget child;
        if (snapshot.connectionState == ConnectionState.waiting) {
          child = expand
              ? const SizedBox.expand(child: Center(child: CircularProgressIndicator()))
              : SizedBox(
                  height: height ?? 200,
                  width: width,
                  child: const Center(child: CircularProgressIndicator()),
                );
        } else if (!snapshot.hasData) {
          child = expand
              ? const SizedBox.expand(child: Icon(Icons.image_not_supported_outlined))
              : SizedBox(
                  height: height,
                  width: width,
                  child: const Icon(Icons.image_not_supported_outlined),
                );
        } else {
          final img = Image.memory(
            snapshot.data!,
            width: expand ? null : (width ?? double.infinity),
            height: expand ? null : height,
            fit: fit,
            alignment: alignment,
          );

          if (expand) {
            child = SizedBox.expand(child: img);
          } else if (height == null) {
            // Sin contenedor ni fondo para evitar bandas
            child = img;
          } else {
            child = Container(
              width: width ?? double.infinity,
              height: height,
              color: backgroundColor,
              alignment: Alignment.center,
              child: img,
            );
          }
        }

        final clipped = ClipRRect(
          borderRadius: radius ?? BorderRadius.circular(10),
          child: child,
        );

        final hero = heroTag != null ? Hero(tag: heroTag, child: clipped) : clipped;
        return GestureDetector(onTap: onTap, child: hero);
      },
    );
  }

  // -------------------- Likes --------------------
  Future<void> _fetchLikes() async {
    final token = await _storage.read(key: 'access_token');
    final pageId = itemData['id']?.toString() ?? '';
    if (token == null || pageId.isEmpty) return;

    final res = await http.get(
      Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/news/get-likes?page_id=$pageId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode == 200) {
      final body = json.decode(res.body);
      _likesList = List<Map<String, dynamic>>.from(body['data'] ?? []);
      likesCount = _likesList.length;
    }
  }

  Future<void> _determineIfUserLiked() async {
    final userEmail = await _storage.read(key: 'user_email');
    if (userEmail == null) return;

    await _fetchLikes();

    final found = _likesList.any((u) =>
        (u['email']?.toString().toLowerCase().trim() ?? '') ==
        userEmail.toLowerCase().trim());

    if (found) {
      // ignore: avoid_print
      print(' El usuario con email $userEmail ya le dio like, no puede volver a dar.');
    }

    if (mounted) setState(() => isLiked = found);
  }

  Future<void> _toggleLike() async {
    final token = await _storage.read(key: 'access_token');
    final pageId = itemData['id']?.toString() ?? '';
    if (token == null || pageId.isEmpty) return;

    final res = await http.post(
      Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/news/toggle-like'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: json.encode({'page_id': pageId}),
    );

    if (res.statusCode == 200) {
      await _determineIfUserLiked();
      if (mounted) setState(() {});
    }
  }

  void _showLikesDialog() async {
    await _fetchLikes();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Personas que dieron Me gusta'),
        content: _likesList.isEmpty
            ? const Text('Nadie ha dado Me gusta o no se pudo cargar.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _likesList.length,
                  itemBuilder: (_, i) {
                    final u = _likesList[i];
                    return ListTile(
                      title: Text('${u['names'] ?? ''} ${u['surnames'] ?? ''}'),
                      subtitle: Text(u['email'] ?? ''),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  // -------------------- Carga y parseo --------------------
  void _loadItemDetails() async {
    itemData = widget.itemData;

    title = itemData['title'] ?? 'Sin título';
    publishedAt = itemData['published_at'] ?? '';
    likesCount = itemData['likes_count'] ?? 0;
    isLiked = itemData['is_liked'] ?? false;

    if (!isLiked) await _determineIfUserLiked();

    final thumb = itemData['thumbnail'];
    if (thumb != null && thumb.toString().isNotEmpty) {
      final cleaned = Uri.encodeFull(thumb.toString().replaceAll(r'\', ''));
      // Thumbnail SIN fondo gris y SIN altura fija: se adapta al ancho (fitWidth)
      _thumbnailWidget = _buildImageWidget(
        cleaned,
        radius: BorderRadius.circular(12),
        heroTag: 'thumb_$cleaned',
        onTap: () => _openImageViewer(
          slides: [
            {'url': cleaned, 'desc': title ?? ''}
          ],
          initialIndex: 0,
          heroSeed: 'thumb_',
        ),
        fit: BoxFit.fitWidth,
        alignment: Alignment.center,
        // height: null => la imagen define su altura; no hay letterboxing
      );
    }

    String sanitizeHtml(String html) => html.replaceAll(
          RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false),
          '',
        );

    final List<dynamic> metaList = itemData['pages_meta'] ?? [];
    for (var meta in metaList) {
      final key = meta['meta_key'];
      final rawValue = meta['meta_value'];
      if (rawValue is! String || rawValue.isEmpty) continue;

      try {
        final parsed = json.decode(rawValue);

        switch (key) {
          case 'image': {
            final url = parsed['image-url'] ?? parsed['image'];
            if (url != null && url.toString().isNotEmpty) {
              final cleaned = Uri.encodeFull(url.toString().replaceAll(r'\', ''));
              _contentWidgets.add(
                _buildImageWidget(
                  cleaned,
                  height: 250,
                  radius: BorderRadius.circular(12),
                  heroTag: 'single_$cleaned',
                  onTap: () => _openImageViewer(
                    slides: [
                      {'url': cleaned, 'desc': ''}
                    ],
                    initialIndex: 0,
                    heroSeed: 'single_',
                  ),
                  fit: BoxFit.cover,
                ),
              );
            }
            break;
          }

          case 'paragraph': {
            final htmlText = parsed['paragraph-text'];
            if (htmlText != null) {
              _contentWidgets.add(Html(
                data: htmlText,
                style: {
                  'p': Style(
                    fontSize: FontSize(16),
                    textAlign: TextAlign.justify,
                    lineHeight: LineHeight.number(1.6),
                  )
                },
              ));
            }
            break;
          }

          case 'title': {
            final titleHtml = parsed['title-text'];
            final level = (parsed['title-principal'] ?? 'h2').toString().toLowerCase();
            double size;
            switch (level) {
              case 'h1': size = 26; break;
              case 'h2': size = 22; break;
              case 'h3': size = 20; break;
              case 'h4': size = 18; break;
              default: size = 16;
            }
            if (titleHtml != null) {
              _contentWidgets.add(Html(
                data: titleHtml,
                style: {'p': Style(fontSize: FontSize(size), fontWeight: FontWeight.bold)},
              ));
            }
            break;
          }

          case 'wysiwyg': {
            final html = parsed['code-text'];
            if (html != null) {
              _contentWidgets.add(Html(
                data: sanitizeHtml(html),
                style: {'p': Style(fontSize: FontSize(16), textAlign: TextAlign.justify)},
              ));
            }
            break;
          }

          case 'list': {
            final items = parsed['lists-text'] as List?;
            if (items != null) {
              _contentWidgets.add(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items
                      .map((e) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Icon(Icons.circle, size: 6, color: Colors.blue)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Html(data: e, style: {'p': Style(margin: Margins.zero)}),
                              ),
                            ],
                          ))
                      .toList(),
                ),
              );
            }
            break;
          }

          case 'featured_link_card': {
            final cards = parsed['cards'] as List?;
            if (cards != null && cards.isNotEmpty) {
              _contentWidgets.addAll(cards.map((card) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    child: ListTile(
                      leading: const Icon(Icons.link, color: Colors.blue),
                      title: Text(card['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: (card['title2'] ?? '').toString().isNotEmpty ? Text(card['title2']) : null,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => launchUrl(Uri.parse(card['link'] ?? ''), mode: LaunchMode.externalApplication),
                    ),
                  )));
            }
            break;
          }

          case 'gallery': {
            try {
              final rawSlides = parsed['slides'];
              List slides;
              if (rawSlides is String) {
                slides = json.decode(rawSlides) as List;
              } else if (rawSlides is List) {
                slides = rawSlides;
              } else {
                slides = const [];
              }

              if (slides.isNotEmpty) {
                final mapped = slides.map<Map<String, String>>((s) {
                  final rawUrl = s['image'] ?? s['url'] ?? '';
                  final url = Uri.encodeFull(rawUrl.toString().replaceAll(r'\', ''));
                  final desc = (s['description'] ?? '').toString();
                  return {'url': url, 'desc': desc};
                }).where((m) => (m['url'] ?? '').isNotEmpty).toList();

                if (mapped.isNotEmpty) {
                  _galleries.add({
                    'title': 'Galería de imágenes',
                    'slides': mapped,
                  });
                }
              }
            } catch (e) {
              // ignore: avoid_print
              print(' Error al procesar galería: $e');
            }
            break;
          }

          case 'button':
          case 'link': {
            final text = parsed['button-text'] ?? parsed['link-text'];
            final url = parsed['button-link'] ?? parsed['link-url'];
            if (text != null && url != null) {
              _contentWidgets.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ElevatedButton(
                    onPressed: () => launchUrl(Uri.parse(url)),
                    child: Text(text),
                  ),
                ),
              );
            }
            break;
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print(' Error al parsear meta_value para $key: $e');
      }
    }

    setState(() => isLoading = false);
  }

  // -------------------- Viewer Fullscreen --------------------
  void _openImageViewer({
    required List<Map<String, String>> slides,
    required int initialIndex,
    String heroSeed = '',
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullScreenImageViewer(
          slides: slides,
          getImageFuture: _getImageFuture,
          initialIndex: initialIndex,
          heroSeed: heroSeed,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title ?? 'Detalle del ítem')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: CustomScrollView(
                slivers: [
                  // Header (thumbnail, título, likes, comentarios, fecha)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_thumbnailWidget != null) _thumbnailWidget!,
                        if (_thumbnailWidget != null) const SizedBox(height: 12),
                        Text(title ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _toggleLike,
                              child: Icon(
                                isLiked ? Icons.favorite : Icons.favorite_border_outlined,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _showLikesDialog,
                              child: Text(
                                '$likesCount Me gusta',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            InkWell(
                              onTap: _openComments,
                              child: Row(
                                children: const [
                                  Icon(Icons.mode_comment_outlined),
                                  SizedBox(width: 6),
                                  Text('Comentarios',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('Publicado el: $publishedAt', style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  // Contenido (párrafos, títulos, imágenes sueltas, etc.)
                  if (_contentWidgets.isNotEmpty)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _contentWidgets[index],
                        ),
                        childCount: _contentWidgets.length,
                      ),
                    ),

                  // Galerías (lazy-load con SliverGrid)
                  for (final gal in _galleries) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(gal['title'] as String,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(bottom: 12),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final slides = (gal['slides'] as List).cast<Map<String, String>>();
                            final s = slides[i];
                            final url = s['url']!;
                            final desc = s['desc'] ?? '';
                            final heroTag = 'gal_${url}_$i';
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  // Llenar la celda completa sin usar alturas infinitas:
                                  _buildImageWidget(
                                    url,
                                    expand: true,
                                    radius: BorderRadius.zero,
                                    heroTag: heroTag,
                                    onTap: () => _openImageViewer(
                                      slides: slides,
                                      initialIndex: i,
                                      heroSeed: 'gal_',
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                  if (desc.isNotEmpty)
                                    Positioned(
                                      bottom: 0, left: 0, right: 0,
                                      child: Container(
                                        color: Colors.black.withOpacity(0.55),
                                        padding: const EdgeInsets.all(6),
                                        child: Text(
                                          desc,
                                          style: const TextStyle(color: Colors.white, fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                          childCount: (gal['slides'] as List).length,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

// =================== Viewer de imágenes (pantalla completa) ===================
class _FullScreenImageViewer extends StatefulWidget {
  final List<Map<String, String>> slides;
  final Future<Uint8List?> Function(String url) getImageFuture;
  final int initialIndex;
  final String heroSeed;

  const _FullScreenImageViewer({
    Key? key,
    required this.slides,
    required this.getImageFuture,
    required this.initialIndex,
    required this.heroSeed,
  }) : super(key: key);

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${slides.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: slides.length,
        itemBuilder: (context, i) {
          final url = slides[i]['url']!;
          final desc = slides[i]['desc'] ?? '';
          final heroTag = '${widget.heroSeed}${url}_$i';

          return Center(
            child: FutureBuilder<Uint8List?>(
              future: widget.getImageFuture(url),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator(color: Colors.white);
                }
                if (!snapshot.hasData) {
                  return const Icon(Icons.broken_image, color: Colors.white70, size: 48);
                }
                return Column(
                  children: [
                    Expanded(
                      child: Hero(
                        tag: heroTag,
                        child: InteractiveViewer(
                          minScale: 0.7,
                          maxScale: 5.0,
                          child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    if (desc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          desc,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
