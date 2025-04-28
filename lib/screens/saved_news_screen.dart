import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:carousel_slider/carousel_slider.dart';

final _storage = FlutterSecureStorage();

class SavedNewsScreen extends StatefulWidget {
  const SavedNewsScreen({Key? key}) : super(key: key);

  @override
  State<SavedNewsScreen> createState() => _SavedNewsScreenState();
}

class _SavedNewsScreenState extends State<SavedNewsScreen> {
  List<Map<String, dynamic>> savedNews = [];
  bool isLoading = true;

  final Map<int, int> _carouselIndexes = {};            
  final Map<String, Future<Uint8List?>> _imageFutures = {}; 
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _isFetchingMore = false;
  bool _hasMorePages = true;

  @override
  void initState() {
    super.initState();
    _fetchSavedPosts(page: _currentPage, append: false);
    _scrollController.addListener(_onScroll);            
  }

  @override
  void dispose() {
    _scrollController.dispose();                         
    super.dispose();
  }
  void _onScroll() {
    const threshold = 300; // px antes del fondo
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - threshold &&
        !_isFetchingMore &&
        _hasMorePages) {
      _loadNextPage();
    }
  }
  Future<void> _loadNextPage() async {
    _isFetchingMore = true;
    _currentPage++;
    await _fetchSavedPosts(page: _currentPage, append: true);
    _isFetchingMore = false;
  }
  Future<Uint8List?> fetchImageBytes(String imageUrl) async {
    try {
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Referer': 'https://chileatiende.gob.cl',
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        },
      );
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (e) {
      debugPrint(' Excepción al descargar la imagen: $e');
      return null;
    }
  }

  Future<Uint8List?> _getImageFuture(String url) {
    return _imageFutures.putIfAbsent(url, () => fetchImageBytes(url));
  }

 Widget _buildImageWidget(String url) {
  return FutureBuilder<Uint8List?>(
    future: _getImageFuture(url),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return SizedBox(
          height: 250,
          child: Center(
            child: SizedBox(
              width: 50,   
              height: 50,  
              child: const CircularProgressIndicator(),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return Image.asset(
          'assets/icons/default_news.png',
          fit: BoxFit.cover,
          height: 250,
          width: double.infinity,
        );
      }
      return Image.memory(
        snapshot.data!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 250,
      );
    },
  );
}
  Future<void> _fetchSavedPosts(
      {required int page, required bool append}) async {
    try {
      final userId = await _storage.read(key: 'user_id');
      final token = await _storage.read(key: 'access_token');
      if (userId == null || token == null) {
        throw Exception('Credenciales no encontradas');
      }

      final uri = Uri.parse(
          'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/saved-posts?app_user_id=$userId&page=$page');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<Map<String, dynamic>> newPosts =
            List<Map<String, dynamic>>.from(data['data'] ?? []);

        setState(() {
          if (append) {
            savedNews.addAll(newPosts);
          } else {
            savedNews = newPosts;
          }

          if (newPosts.isEmpty) {
            _hasMorePages = false; 
          }

          isLoading = false;
        });
      } else {
        throw Exception('Error ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error posts guardados: $e');
      setState(() => isLoading = false);
      _hasMorePages = false;
    }
  }
  Widget _buildPostCard(Map<String, dynamic> post, int postIndex) {
    List<dynamic> metaData = [];
    try {
      if (post['meta_key'] != null && post['meta_key'].isNotEmpty) {
        metaData = json.decode(post['meta_key']);
      }
    } catch (_) {}
    List<String> images = [];
    for (var item in metaData) {
      if (item['type'] == 'image-carousel' && item['cards'] is List) {
        images = List<String>.from(
            (item['cards'] as List).map((e) => e['image'] ?? ''));
        break;
      }
    }
    if (images.isEmpty) {
      for (var item in metaData) {
        if (item['type'] == 'image' && item['image'] != null) {
          images = [item['image'] as String];
          break;
        }
      }
    }
    String description = '';
    for (var item in metaData) {
      if (item['type'] == 'paragraph' && item.containsKey('paragraph-text')) {
        description = (item['paragraph-text'] as String)
            .replaceAll('<p>', '')
            .replaceAll('</p>', '');
        break;
      }
    }

    _carouselIndexes.putIfAbsent(postIndex, () => 0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12,
              blurRadius: 5,
              spreadRadius: 2,
              offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                const CircleAvatar(radius: 20, backgroundColor: Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post['title'] ?? 'Sin título',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      Text(post['published_at'] ?? 'Sin fecha',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (images.isNotEmpty)
            Column(
              children: [
                CarouselSlider.builder(
                  itemCount: images.length,
                  itemBuilder: (_, i, __) => _buildImageWidget(images[i]),
                  options: CarouselOptions(
                    viewportFraction: 1,
                    height: 250,
                    enableInfiniteScroll: images.length > 1,
                    onPageChanged: (idx, _) =>
                        setState(() => _carouselIndexes[postIndex] = idx),
                  ),
                ),
                if (images.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(images.length, (dotIdx) {
                        final active = _carouselIndexes[postIndex] == dotIdx;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 10 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active ? Colors.blue : Colors.grey,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            )
          else
            ClipRRect(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12)),
              child:
                  _buildImageWidget(''), 
            ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Html(
              data: description.isNotEmpty
                  ? description
                  : '<p>Sin descripción disponible.</p>',
              style: {
                'p': Style(
                    fontSize: FontSize(14),
                    color: Colors.black87,
                    textAlign: TextAlign.justify),
                'a': Style(
                    color: Colors.blue,
                    textDecoration: TextDecoration.underline),
              },
              onLinkTap: (url, _, __) async {
                if (url != null && await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : savedNews.isEmpty
              ? const Center(
                  child:
                      Text('No tienes noticias guardadas.',
                          style: TextStyle(fontSize: 18)))
              : ListView.builder(
                  controller: _scrollController,            
                  itemCount: savedNews.length +               
                      (_hasMorePages ? 1 : 0),               
                  itemBuilder: (context, index) {
                    if (index >= savedNews.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _buildPostCard(savedNews[index], index);
                  },
                ),
    );
  }
}
