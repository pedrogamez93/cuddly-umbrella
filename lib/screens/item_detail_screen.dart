import 'package:flutter/material.dart';
import 'dart:convert';

class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> itemData; // Receives full item data

  const ItemDetailScreen({Key? key, required this.itemData}) : super(key: key);

  @override
  _ItemDetailScreenState createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late Map<String, dynamic> itemData;
  bool isLoading = true;
  String? imageUrl;
  String? title;
  String? description;
  String? publishedAt;

  @override
  void initState() {
    super.initState();
    _loadItemDetails();
  }

  void _loadItemDetails() {
    setState(() {
      itemData = widget.itemData;

      title = itemData['title'] ?? 'Sin título';
      publishedAt = itemData['published_at'] ?? 'Fecha desconocida';

      // Extract image from pages_meta
      if (itemData['pages_meta'] != null) {
        for (var meta in itemData['pages_meta']) {
          if (meta['meta_key'] == 'image' && meta['meta_value'] is String) {
            final metaValue = json.decode(meta['meta_value']);
            imageUrl = metaValue['image-url'];
          }
          if (meta['meta_key'] == 'paragraph' && meta['meta_value'] is String) {
            final metaValue = json.decode(meta['meta_value']);
            description = metaValue['paragraph-text']
                ?.replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Sin descripción';
          }
        }
      }

      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'Detalle del ítem'),
        backgroundColor: Colors.blue,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: ListView(
                children: [
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        imageUrl!,
                        width: double.infinity,
                        height: 250,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: 250,
                            color: Colors.grey[300],
                            child: const Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    title ?? 'Sin título',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Publicado el: ${publishedAt ?? 'Fecha desconocida'}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    description ?? 'No hay descripción disponible.',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.justify,
                  ),
                ],
              ),
            ),
    );
  }
}
