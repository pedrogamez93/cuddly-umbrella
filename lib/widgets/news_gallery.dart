import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class NewsGallery extends StatelessWidget {
  final List<String> imageUrls;
  final double spacing;
  final int? crossAxisCount; // si quieres forzar columnas; si no, se calcula

  const NewsGallery({
    Key? key,
    required this.imageUrls,
    this.spacing = 6,
    this.crossAxisCount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Cálculo responsivo de columnas si no fue forzado
        final cols = crossAxisCount ??
            (width >= 1200 ? 5 : width >= 900 ? 4 : width >= 600 ? 3 : 2);
        final tileSize = (width - (spacing * (cols - 1))) / cols;
        final deviceRatio = MediaQuery.of(context).devicePixelRatio;
        // Cache de imagen por tamaño del tile en píxeles reales
        final memCacheW = (tileSize * deviceRatio).clamp(200, 1200).toInt();

        return GridView.builder(
          key: const PageStorageKey('news_gallery_grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: imageUrls.length,
          itemBuilder: (context, index) {
            final url = imageUrls[index];
            return _GalleryTile(
              url: url,
              index: index,
              memCacheWidth: memCacheW,
              onTap: () => _openFullScreen(context, imageUrls, index),
            );
          },
        );
      },
    );
  }

  void _openFullScreen(BuildContext context, List<String> urls, int initial) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.9),
        pageBuilder: (_, __, ___) => _FullScreenGallery(
          imageUrls: urls,
          initialIndex: initial,
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final String url;
  final int index;
  final int memCacheWidth;
  final VoidCallback onTap;

  const _GalleryTile({
    Key? key,
    required this.url,
    required this.index,
    required this.memCacheWidth,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tag = 'news_gallery_$index-$url'; // tag único para Hero

    return Hero(
      tag: tag,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: memCacheWidth,
              fadeInDuration: const Duration(milliseconds: 220),
              fadeOutDuration: const Duration(milliseconds: 120),
              progressIndicatorBuilder: (_, __, progress) {
                return Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      value: progress.progress,
                    ),
                  ),
                );
              },
              errorWidget: (_, __, ___) => Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenGallery extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullScreenGallery({
    Key? key,
    required this.imageUrls,
    required this.initialIndex,
  }) : super(key: key);

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
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
    final urls = widget.imageUrls;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (_) => Navigator.pop(context), // gesto para cerrar
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: urls.length,
            itemBuilder: (_, i) {
              final url = urls[i];
              final tag = 'news_gallery_$i-$url';
              return Center(
                child: Hero(
                  tag: tag,
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0,
                    clipBehavior: Clip.none,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      fadeInDuration: const Duration(milliseconds: 220),
                      progressIndicatorBuilder: (_, __, progress) {
                        return SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            value: progress.progress,
                          ),
                        );
                      },
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                ),
              );
            },
          ),

          // Cerrar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Cerrar',
            ),
          ),

          // Indicador
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Text(
              '${_index + 1} / ${urls.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
