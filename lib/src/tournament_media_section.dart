import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models.dart';
import 'repositories.dart';

class TournamentMediaSection extends StatefulWidget {
  const TournamentMediaSection({
    super.key,
    required this.repository,
    required this.tournament,
    required this.username,
    required this.onChanged,
  });

  final LeagueRepository repository;
  final Tournament tournament;
  final String? username;
  final ValueChanged<List<TournamentMedia>> onChanged;

  @override
  State<TournamentMediaSection> createState() => _TournamentMediaSectionState();
}

class _TournamentMediaSectionState extends State<TournamentMediaSection> {
  final ImagePicker picker = ImagePicker();
  bool loading = false;
  String? error;

  List<TournamentMedia> get media => widget.tournament.media;

  Future<void> refreshMedia() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final nextMedia = await widget.repository.tournamentMedia(
        widget.tournament,
      );
      if (mounted) {
        widget.onChanged(nextMedia);
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'Не удалось загрузить медиа: $exception');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> addMedia(TournamentMediaKind kind) async {
    final source = await _pickSource(kind);
    if (source == null) {
      return;
    }

    final file = kind == TournamentMediaKind.photo
        ? await picker.pickImage(source: source, imageQuality: 88)
        : await picker.pickVideo(source: source);
    if (file == null) {
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });
    try {
      final uploaded = await widget.repository.uploadTournamentMedia(
        tournament: widget.tournament,
        kind: kind,
        filename: file.name,
        bytes: await file.readAsBytes(),
        uploadedBy: widget.username ?? '',
        title: file.name,
      );
      if (!mounted) {
        return;
      }
      widget.onChanged([uploaded, ...media]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${kind.label} добавлено к турниру')),
      );
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'Не удалось загрузить файл: $exception');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<ImageSource?> _pickSource(TournamentMediaKind kind) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          children: [
            Text(
              kind == TournamentMediaKind.photo
                  ? 'Добавить фото'
                  : 'Добавить видео',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Камера'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Галерея телефона'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.perm_media_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Фото и записи',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: loading ? null : refreshMedia,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: loading
                        ? null
                        : () => addMedia(TournamentMediaKind.photo),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Фото'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: loading
                        ? null
                        : () => addMedia(TournamentMediaKind.video),
                    icon: const Icon(Icons.video_call_outlined),
                    label: const Text('Видео'),
                  ),
                ),
              ],
            ),
            if (loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            if (media.isEmpty)
              Text(
                'Материалов пока нет.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileWidth = constraints.maxWidth >= 460
                      ? (constraints.maxWidth - 18) / 3
                      : (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      for (final item in media)
                        SizedBox(
                          width: tileWidth,
                          child: _TournamentMediaTile(media: item),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TournamentMediaTile extends StatelessWidget {
  const _TournamentMediaTile({required this.media});

  final TournamentMedia media;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: media.url.isEmpty ? null : () => _openMedia(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xffdce2d6)),
          borderRadius: BorderRadius.circular(8),
          color: scheme.surface,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!media.isVideo && media.url.isNotEmpty)
                  Image.network(
                    media.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _MediaFallback(media: media),
                  )
                else
                  _MediaFallback(media: media),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        media.title.isEmpty ? media.kind.label : media.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMedia(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _TournamentMediaViewer(media: media)),
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback({required this.media});

  final TournamentMedia media;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          media.isVideo ? Icons.play_circle_outline : Icons.image_outlined,
          size: 42,
          color: scheme.primary,
        ),
      ),
    );
  }
}

class _TournamentMediaViewer extends StatelessWidget {
  const _TournamentMediaViewer({required this.media});

  final TournamentMedia media;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(media.kind.label)),
      body: media.isVideo
          ? WebViewWidget(
              controller: WebViewController()
                ..setJavaScriptMode(JavaScriptMode.unrestricted)
                ..loadRequest(Uri.parse(media.url)),
            )
          : InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  media.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 56),
                ),
              ),
            ),
    );
  }
}
