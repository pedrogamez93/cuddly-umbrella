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
  final _storage = FlutterSecureStorage();

  String? profileImage = 'https://via.placeholder.com/150';
  String? fullname = 'Cargando...';
  String? email = 'Cargando...';
  String? officeLocation = 'Cargando...';

  List<Map<String, dynamic>> likedPosts = [];
  bool isLoading = true;
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _isFetchingMore = false;
  bool _hasMorePages = true;
  final Map<String, Future<Uint8List?>> _imageFutures = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
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
    final storedUserId = await _storage.read(key: 'user_id');
    final storedAccessToken = await _storage.read(key: 'access_token');
    if (storedUserId != null && storedAccessToken != null) {
      await _fetchLikedPosts(int.parse(storedUserId), storedAccessToken,
          page: _currentPage, append: true);
    }
    _isFetchingMore = false;
  }
  Future<void> _loadUserData() async {
    String? storedFullname = await _storage.read(key: 'user_full_name');
    String? storedEmail = await _storage.read(key: 'user_email');
    String? storedUserId = await _storage.read(key: 'user_id');
    String? storedAccessToken = await _storage.read(key: 'access_token');

    setState(() {
      fullname = storedFullname ?? 'No disponible';
      email = storedEmail ?? 'No disponible';
    });

    if (storedUserId != null && storedAccessToken != null) {
      final decodedofficeLocation =
          decodeofficeLocationFromAccessToken(storedAccessToken);
      if (decodedofficeLocation != null) {
        setState(() => officeLocation = decodedofficeLocation);
      }
      _currentPage = 1;
      _hasMorePages = true;
      await _fetchLikedPosts(int.parse(storedUserId), storedAccessToken,
          page: _currentPage, append: false);
    }
  }
  String? decodeofficeLocationFromAccessToken(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) return null;
      final normalizedPayload = base64Url.normalize(parts[1]);
      final decodedPayload =
          utf8.decode(base64Url.decode(normalizedPayload));
      final payloadMap = json.decode(decodedPayload);

      final String? jwtCu = payloadMap['jwt_cu'];
      if (jwtCu == null) return null;

      final partsCU = jwtCu.split('.');
      if (partsCU.length != 3) return null;
      final normalizedPayloadCU = base64Url.normalize(partsCU[1]);
      final decodedPayloadCU =
          utf8.decode(base64Url.decode(normalizedPayloadCU));
      final payloadMapCU = json.decode(decodedPayloadCU);

      return payloadMapCU['officeLocation'];
    } catch (_) {
      return null;
    }
  }
  Future<Uint8List?> fetchImageBytes(String imageUrl) async {
    try {
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Referer': 'https://chileatiende.gob.cl',
        },
      );
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _getImageFuture(String url) =>
      _imageFutures.putIfAbsent(url, () => fetchImageBytes(url));

  Widget _buildImageWidget(String url) => FutureBuilder<Uint8List?>(
        future: _getImageFuture(url),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData) {
            return Image.asset('assets/icons/default_image.png',
                fit: BoxFit.cover);
          }
          return Image.memory(snap.data!, fit: BoxFit.cover);
        },
      );
  Future<void> _fetchLikedPosts(int userId, String token,
      {required int page, required bool append}) async {
    final url =
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-posts-app-user?app_user_id=$userId&page=$page';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['data'] != null) {
          List<Map<String, dynamic>> newPosts = [];

          for (var post in data['data']) {
            try {
              final List<dynamic> metaKeyList = json.decode(post['meta_key']);
              String? firstImage;
              String? content;
              List<String> imagesList = [];

              for (var meta in metaKeyList) {
                if (meta['type'] == 'image-carousel' &&
                    meta['cards'] is List) {
                  imagesList = List<String>.from(
                      (meta['cards'] as List).map((c) => c['image'] ?? ''));
                  if (imagesList.isNotEmpty) firstImage = imagesList[0];
                  break;
                }
              }
              if (imagesList.isEmpty) {
                for (var meta in metaKeyList) {
                  if (meta['type'] == 'image' && meta['image'] != null) {
                    firstImage = meta['image'];
                    imagesList = [if (firstImage != null) firstImage];
                    break;
                  }
                }
              }
              if (firstImage != null) {
                firstImage = Uri.encodeFull(firstImage.replaceAll(r'\', '').trim());
              }

              for (var meta in metaKeyList) {
                if (meta['type'] == 'paragraph') {
                  content = meta['paragraph-text'];
                  break;
                }
              }

              newPosts.add({
                'id': post['id'],
                'title': post['title'],
                'image': firstImage ?? 'https://via.placeholder.com/150',
                'images':
                    imagesList.isNotEmpty ? imagesList : [firstImage ?? ''],
                'content': content ?? 'Sin contenido disponible',
                'likes': post['likes_count'],
                'comments': post['comments_count'],
                'published_at': post['published_at'],
              });
            } catch (e) {
            }
          }

          setState(() {
            if (append) {
              likedPosts.addAll(newPosts);
            } else {
              likedPosts = newPosts;
            }
            isLoading = false;
            if (newPosts.isEmpty) _hasMorePages = false; 
          });
        } else {
          setState(() => _hasMorePages = false);         
        }
      } else {
        _hasMorePages = false;                          
      }
    } catch (_) {
      _hasMorePages = false;                           
    }
  }
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,                  
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(radius: 50, backgroundImage: NetworkImage(profileImage!)),
                  const SizedBox(height: 16),
                  Text(fullname!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(email!, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(officeLocation ?? 'No disponible',
                      style: const TextStyle(fontSize: 14, color: Colors.black54)),
                  const SizedBox(height: 24),
                  Row(
                    children: const [
                      Icon(Icons.favorite),
                      SizedBox(width: 8),
                      Text('Mis me gusta',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (likedPosts.isEmpty)
            const SliverFillRemaining(
              child: Center(
                  child: Text('No tienes posts marcados con "Me gusta".',
                      style: TextStyle(fontSize: 14, color: Colors.grey))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= likedPosts.length) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final post = likedPosts[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SinglePostScreen(post: post),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildImageWidget(post['image']),
                      ),
                    );
                  },
                  childCount:
                      likedPosts.length + (_hasMorePages ? 1 : 0),       
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
