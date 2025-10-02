import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

class PostCard extends StatefulWidget {
  final int postId;
  final String title;
  final DateTime? publishedAt;
  final List<String> imageUrls;
  final String paragraphHtml;
  final bool isLiked;
  final bool isSaved;
  final int likeCount;
  final int commentCount; // <- NUEVO
  final VoidCallback onToggleLike;
  final VoidCallback onToggleSave;
  final VoidCallback onTapLikes;
  final VoidCallback onTapComments;

  const PostCard({
    super.key,
    required this.postId,
    required this.title,
    required this.publishedAt,
    required this.imageUrls,
    required this.paragraphHtml,
    required this.isLiked,
    required this.isSaved,
    required this.likeCount,
    required this.commentCount, // <- NUEVO
    required this.onToggleLike,
    required this.onToggleSave,
    required this.onTapLikes,
    required this.onTapComments,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    final timeText = widget.publishedAt != null
        ? timeago.format(widget.publishedAt!, locale: 'es')
        : 'Fecha desconocida';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.access_time, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Text(timeText, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            ]),
            const SizedBox(height: 8),

            // Imagen / Galería
            if (widget.imageUrls.isEmpty)
              Image.asset('assets/images/placeholder.png', height: 250, fit: BoxFit.cover)
            else if (widget.imageUrls.length == 1)
              _cachedImage(widget.imageUrls.first)
            else
              Column(
                children: [
                  CarouselSlider(
                    options: CarouselOptions(
                      height: 250, viewportFraction: 1.0, enableInfiniteScroll: false,
                      enlargeCenterPage: false,
                      onPageChanged: (i, _) => setState(() => _current = i),
                    ),
                    items: widget.imageUrls.map((u) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _cachedImage(u),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.imageUrls.length, (i) {
                      final active = _current == i;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: active ? 12 : 8, height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? Colors.blueAccent : Colors.grey[400],
                        ),
                      );
                    }),
                  )
                ],
              ),

            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  IconButton(
                    icon: Icon(
                      widget.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: widget.isLiked ? Colors.red : Colors.black,
                    ),
                    onPressed: widget.onToggleLike,
                  ),
                  // Likes
                  GestureDetector(
                    onTap: widget.onTapLikes,
                    child: Text(
                      '${widget.likeCount} Me gusta',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Comentarios: ícono + número
                  InkWell(
                    onTap: widget.onTapComments,
                    child: Row(
                      children: [
                        const Icon(Icons.mode_comment_outlined, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.commentCount}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
                IconButton(
                  icon: Icon(
                    widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: widget.isSaved ? Colors.amber : Colors.black,
                  ),
                  onPressed: widget.onToggleSave,
                ),
              ],
            ),

            Html(
              data: widget.paragraphHtml,
              style: {
                "p": Style(fontSize: FontSize(14), textAlign: TextAlign.justify),
                "a": Style(textDecoration: TextDecoration.underline),
              },
              onLinkTap: (url, attrs, el) async {
                if (url == null) return;
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _cachedImage(String url) => CachedNetworkImage(
        imageUrl: url,
        httpHeaders: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/115 Safari/537.36',
          'Referer': 'https://chileatiende.gob.cl',
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        },
        height: 250,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            const SizedBox(height: 250, child: Center(child: CircularProgressIndicator())),
        errorWidget: (_, __, ___) =>
            Image.asset('assets/images/placeholder.png', height: 250, fit: BoxFit.cover),
      );
}
