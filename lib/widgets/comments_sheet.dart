// lib/widgets/comments_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/comment.dart';
import '../models/paged.dart';
import '../services/comments_api.dart';

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    this.postId,
    this.pageId,
  }) : assert(postId != null || pageId != null);

  final int? postId;
  final int? pageId;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _api = CommentsApi();
  final _storage = const FlutterSecureStorage();
  final _controller = TextEditingController();

  int _appUserId = -1;
  String? _userEmail;

  Paged<Comment>? _paged;
  bool _loading = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _appUserId = int.tryParse(await _storage.read(key: 'user_id') ?? '') ?? -1;
    _userEmail = await _storage.read(key: 'user_email'); // para 3 puntos
    await _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final res = await _api.getComments(
        postId: widget.postId,
        pageId: widget.pageId,
        page: page,
        perPage: 10,
      );
      setState(() {
        _paged = res;
        _page = page;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      await _showAuthDialog(e.message);
      Navigator.of(context).pop(); // cierra el sheet para que vuelvan a loguearse
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final text = _controller.text.trim();
    if (text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El comentario debe tener al menos 5 caracteres')),
      );
      return;
    }
    try {
      await _api.createComment(
        appUserId: _appUserId,
        content: text,
        postId: widget.postId,
        pageId: widget.pageId,
      );
      _controller.clear();
      await _load(page: 1);
    } on AuthException catch (e) {
      await _showAuthDialog(e.message);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleLike(Comment c) async {
    try {
      await _api.toggleLike(appUserId: _appUserId, commentId: c.id);
      await _load(page: _page);
    } on AuthException catch (e) {
      await _showAuthDialog(e.message);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _openReplies(Comment c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ChildCommentsPage(
        parent: c,
        api: _api,
        appUserId: _appUserId,
        ownerEmail: _userEmail,
      ),
    ));
  }

  void _edit(Comment c) async {
    final txt = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController(text: c.content);
        return AlertDialog(
          title: const Text('Editar comentario'),
          content: TextField(
            controller: ctrl,
            maxLength: 500,
            maxLines: 5,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Guardar')),
          ],
        );
      },
    );
    if (txt == null || txt.length < 5) return;
    try {
      await _api.updateComment(appUserId: _appUserId, commentId: c.id, content: txt);
      await _load(page: _page);
    } on AuthException catch (e) {
      await _showAuthDialog(e.message);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _delete(Comment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar comentario'),
        content: const Text('¿Seguro que deseas eliminar este comentario?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteComment(appUserId: _appUserId, commentId: c.id);
      await _load(page: 1);
    } on AuthException catch (e) {
      await _showAuthDialog(e.message);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _relTime(DateTime dt) => timeago.format(dt, locale: 'es');

  bool _isMine(Comment c) {
    if (_userEmail == null || c.email == null) return false;
    return c.email!.toLowerCase() == _userEmail!.toLowerCase();
  }

  Widget _action({required IconData icon, required String label, VoidCallback? onTap}) {
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18),
      const SizedBox(width: 6),
      Text(label),
    ]);
    return onTap == null
        ? row
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: row,
            ),
          );
  }

  Future<void> _showAuthDialog(String msg) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sesión expirada'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _paged?.data ?? const <Comment>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 10),
            Text(widget.postId != null ? 'Comentarios del Post' : 'Comentarios de la Página',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const Divider(),

            // input crear
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un comentario…',
                        border: OutlineInputBorder(),
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: _create, icon: const Icon(Icons.send)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(child: Text('Sin comentarios'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final c = items[i];
                            final fullName = (c.names ?? 'Usuario') + (c.surnames != null ? ' ${c.surnames}' : '');

                            return ListTile(
                              leading: const Icon(Icons.account_circle, size: 32),
                              title: Text(fullName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Texto + botón Responder
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: Text(c.content)),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () => _openReplies(c),
                                        icon: const Icon(Icons.reply, size: 18),
                                        label: const Text('Responder'),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Acciones: Wrap (fila cuando cabe, quiebra si no)
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(_relTime(c.createdAt), style: Theme.of(context).textTheme.bodySmall),
                                      _action(icon: Icons.thumb_up_alt_outlined, label: '${c.likesCount}', onTap: () => _toggleLike(c)),
                                      if ((c.childCommentsCount ?? 0) > 0)
                                        _action(icon: Icons.forum_outlined, label: '${c.childCommentsCount} resp.', onTap: () => _openReplies(c)),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: _isMine(c)
                                  ? PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'edit') _edit(c);
                                        if (v == 'del') _delete(c);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                                        PopupMenuItem(value: 'del', child: Text('Eliminar')),
                                      ],
                                    )
                                  : null,
                              onTap: () => _openReplies(c),
                            );
                          },
                        ),
            ),

            if (_paged?.lastPage != null && (_paged!.lastPage!) > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(onPressed: _page > 1 ? () => _load(page: _page - 1) : null, icon: const Icon(Icons.chevron_left)),
                  Text('Página $_page / ${_paged!.lastPage!}'),
                  IconButton(onPressed: (_paged!.lastPage!) > _page ? () => _load(page: _page + 1) : null, icon: const Icon(Icons.chevron_right)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ChildCommentsPage extends StatefulWidget {
  const _ChildCommentsPage({
    required this.parent,
    required this.api,
    required this.appUserId,
    required this.ownerEmail,
  });

  final Comment parent;
  final CommentsApi api;
  final int appUserId;
  final String? ownerEmail;

  @override
  State<_ChildCommentsPage> createState() => _ChildCommentsPageState();
}

class _ChildCommentsPageState extends State<_ChildCommentsPage> {
  Paged<Comment>? _paged;
  bool _loading = true;
  int _page = 1;
  final _replyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getChildComments(commentId: widget.parent.id, page: page);
      setState(() {
        _paged = res;
        _page = page;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(title: const Text('Sesión expirada'), content: Text(e.message), actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ]),
      );
      Navigator.of(context).pop();
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reply() async {
    final txt = _replyCtrl.text.trim();
    if (txt.length < 5) return;
    try {
      await widget.api.createComment(
        appUserId: widget.appUserId,
        commentId: widget.parent.id,
        content: txt,
      );
      _replyCtrl.clear();
      await _load(page: 1);
    } on AuthException catch (e) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(title: const Text('Sesión expirada'), content: Text(e.message), actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ]),
      );
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _relTime(DateTime dt) => timeago.format(dt, locale: 'es');

  bool _isMine(Comment c) {
    if (widget.ownerEmail == null || c.email == null) return false;
    return c.email!.toLowerCase() == widget.ownerEmail!.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final list = _paged?.data ?? const <Comment>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Respuestas')),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.comment),
            title: Text(widget.parent.content, maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: Text('de ${(widget.parent.names ?? 'Usuario')} · ${_relTime(widget.parent.createdAt)}'),
          ),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(child: Text('Aún sin respuestas'))
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final fullName = (c.names ?? 'Usuario') + (c.surnames != null ? ' ${c.surnames}' : '');
                          return ListTile(
                            leading: const Icon(Icons.subdirectory_arrow_right),
                            title: Text(fullName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.content),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(_relTime(c.createdAt), style: Theme.of(context).textTheme.bodySmall),
                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.favorite_border, size: 16),
                                      const SizedBox(width: 4),
                                      Text('${c.likesCount}'),
                                    ]),
                                  ],
                                ),
                              ],
                            ),
                            trailing: _isMine(c)
                                ? PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') _edit(c);
                                      if (v == 'del') _delete(c);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                                      PopupMenuItem(value: 'del', child: Text('Eliminar')),
                                    ],
                                  )
                                : null,
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Responder…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: _reply, icon: const Icon(Icons.send)),
              ],
            ),
          ),
          if (_paged?.total != null && (_paged!.total!) > 10)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(onPressed: _page > 1 ? () => _load(page: _page - 1) : null, icon: const Icon(Icons.chevron_left)),
                Text('Página $_page'),
                IconButton(onPressed: true ? () => _load(page: _page + 1) : null, icon: const Icon(Icons.chevron_right)),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _edit(Comment c) async {
    final txt = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController(text: c.content);
        return AlertDialog(
          title: const Text('Editar respuesta'),
          content: TextField(
            controller: ctrl,
            maxLength: 500,
            maxLines: 5,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Guardar')),
          ],
        );
      },
    );
    if (txt == null || txt.length < 5) return;
    try {
      await widget.api.updateComment(appUserId: widget.appUserId, commentId: c.id, content: txt);
      await _load(page: _page);
    } on AuthException catch (e) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(title: const Text('Sesión expirada'), content: Text(e.message), actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ]),
      );
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _delete(Comment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar respuesta'),
        content: const Text('¿Seguro que deseas eliminar esta respuesta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteComment(appUserId: widget.appUserId, commentId: c.id);
      await _load(page: 1);
    } on AuthException catch (e) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(title: const Text('Sesión expirada'), content: Text(e.message), actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ]),
      );
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
