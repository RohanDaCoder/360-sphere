import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/sphere_repository.dart';
import '../core/theme.dart';
import '../maps/publish_sheet.dart';
import '../share/share_service.dart';
import '../viewer/sphere_viewer_screen.dart';

/// Detail page for one photosphere: preview, actions (view / share / save /
/// publish to Google Maps / delete), Street View status.
class SphereDetailScreen extends StatefulWidget {
  const SphereDetailScreen({super.key, required this.sphereId});

  final String sphereId;

  @override
  State<SphereDetailScreen> createState() => _SphereDetailScreenState();
}

class _SphereDetailScreenState extends State<SphereDetailScreen> {
  Photosphere? _sphere;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<SphereRepository>();
      final all = await repo.list();
      if (!mounted) return;
      final match = all.where((s) => s.id == widget.sphereId).firstOrNull;
      if (match == null) {
        setState(() => _error = 'This 360° photo no longer exists.');
        return;
      }
      setState(() => _sphere = match);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sphere = _sphere;
    if (sphere == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(_error ?? 'Loading…',
              style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    final repo = context.read<SphereRepository>();
    final imageFile = File(repo.imagePath(sphere));

    return Scaffold(
      appBar: AppBar(
        title: Text(sphere.name),
        actions: [
          IconButton(
            onPressed: () => _rename(context, sphere),
            icon: const Icon(Icons.edit),
            tooltip: 'Rename',
          ),
          IconButton(
            onPressed: () => _confirmDelete(context, sphere),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Equirectangular preview.
          AspectRatio(
            aspectRatio: 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppTheme.surface,
              ),
              clipBehavior: Clip.antiAlias,
              child: imageFile.existsSync()
                  ? Image.file(imageFile, fit: BoxFit.cover)
                  : const Center(
                      child: Text('Image missing',
                          style: TextStyle(color: Colors.white38)),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (sphere.streetViewPhotoId != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.ok.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public, color: AppTheme.ok, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Published to Google Street View (${sphere.streetViewPhotoId})',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _metaLine(sphere),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SphereViewerScreen(
                imagePath: repo.imagePath(sphere),
                title: sphere.name,
                onShare: () => ShareService.shareFile(repo.imagePath(sphere)),
                onSave: () async {
                  await ShareService.saveToGallery(repo.imagePath(sphere));
                  _toast('Saved to gallery');
                },
                onDelete: () => _confirmDelete(context, sphere),
              ),
            )),
            icon: const Icon(Icons.threed_rotation),
            label: const Text('View in 360°'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _guard(() async {
              await ShareService.shareFile(repo.imagePath(sphere));
            }),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _guard(() async {
              await ShareService.saveToGallery(repo.imagePath(sphere));
              _toast('Saved to gallery');
            }),
            icon: const Icon(Icons.save_alt),
            label: const Text('Save to gallery'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              side: const BorderSide(color: AppTheme.accent),
            ),
            onPressed: sphere.streetViewPhotoId == null
                ? () => showPublishSheet(
                      context,
                      imagePath: repo.imagePath(sphere),
                      onPublished: (photoId) async {
                        sphere.streetViewPhotoId = photoId;
                        await repo.update(sphere);
                        _load();
                      },
                    )
                : null,
            icon: const Icon(Icons.public),
            label: Text(sphere.streetViewPhotoId == null
                ? 'Publish to Google Maps'
                : 'Already on Google Maps'),
          ),
        ],
      ),
    );
  }

  String _metaLine(Photosphere s) =>
      '${s.width}×${s.height} · ${s.frameCount} frames · '
      '${s.createdAt.toLocal().toString().substring(0, 16)}'
      '${s.watermarked ? ' · watermarked' : ''}';

  void _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(BuildContext context, Photosphere sphere) async {
    final repo = context.read<SphereRepository>();
    final controller = TextEditingController(text: sphere.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Rename', style: TextStyle(fontFamily: 'Montserrat')),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await repo.rename(sphere, name);
      if (mounted) _load();
    }
  }

  /// Returns true when the sphere was deleted.
  Future<bool> _confirmDelete(BuildContext context, Photosphere sphere) async {
    final repo = context.read<SphereRepository>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete this 360° photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await repo.delete(sphere);
      if (!mounted) return true;
      Navigator.of(this.context).maybePop();
      return true;
    }
    return false;
  }
}
