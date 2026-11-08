import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../capture/stitching/frame_utils.dart';
import '../capture/stitching/xmp_pano.dart';
import '../core/models.dart';
import '../core/sphere_repository.dart';
import '../core/theme.dart';
import '../capture/camera_screen.dart';
import 'import_service.dart';
import 'sphere_detail_screen.dart';

/// "My 360s" — the gallery grid of captured photospheres.
class My360sScreen extends StatefulWidget {
  const My360sScreen({super.key});

  @override
  State<My360sScreen> createState() => _My360sScreenState();
}

class _My360sScreenState extends State<My360sScreen> {
  late Future<List<Photosphere>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<SphereRepository>().list();
  }

  void _reload() {
    setState(() {
      _future = context.read<SphereRepository>().list();
    });
  }

  bool _importing = false;

  /// Import an existing 360° photo from the device gallery — the original
  /// app's Import button (validated with its "Not a 360° Photo" check:
  /// GPano metadata or a 2:1 equirectangular ratio).
  Future<void> _import() async {
    if (_importing) return;
    final repo = context.read<SphereRepository>();
    setState(() => _importing = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (picked == null) return;
      final bytes = await readFileBytes(picked.path);
      final check = validateForImport(bytes);
      if (check is ImportRejected) {
        _toast(check.reason);
        return;
      }
      final ok = check as ImportOk;

      // Stamp GPano metadata if the source photo lacks it, so imported
      // photos work with Street View / Google Photos like captured ones.
      var jpeg = bytes;
      if (!hasGpanoXmp(bytes)) {
        jpeg = writeGpanoXmp(
          bytes,
          width: ok.width,
          height: ok.height,
          captureSoftware: '360Sphere (imported)',
        );
      }

      final image = await FrameUtils.decodeJpeg(jpeg, maxLongEdge: 4096);
      final thumb = await FrameUtils.makeThumbnail(image);

      final sphere = await repo.save(
        name: 'Imported Photo ${_timestampLabel()}',
        jpeg: jpeg,
        thumb: thumb,
        width: ok.width,
        height: ok.height,
        frameCount: 1,
        watermarked: false,
      );
      if (mounted) {
        _toast('Imported "${sphere.name}"');
        _reload();
      }
    } catch (e) {
      _toast('Failed to import file: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _timestampLabel() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)} ${two(n.hour)}${two(n.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My 360s'),
        actions: [
          IconButton(
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            tooltip: 'Import a 360° photo',
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CameraScreen()),
        ),
        child: const Icon(Icons.photo_camera),
      ),
      body: FutureBuilder<List<Photosphere>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final spheres = snap.data ?? [];
          if (spheres.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: spheres.length,
              itemBuilder: (context, i) {
                final sphere = spheres[i];
                return _SphereTile(
                  sphere: sphere,
                  repository: context.read<SphereRepository>(),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SphereDetailScreen(sphereId: sphere.id),
                    ));
                    _reload();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SphereTile extends StatelessWidget {
  const _SphereTile(
      {required this.sphere, required this.repository, required this.onTap});

  final Photosphere sphere;
  final SphereRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = File(repository.thumbPath(sphere));
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumb.existsSync())
                    Image.file(thumb, fit: BoxFit.cover)
                  else
                    const ColoredBox(color: AppTheme.surfaceHigh),
                  if (sphere.streetViewPhotoId != null)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child:
                          Icon(Icons.public, size: 16, color: Colors.white70),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                sphere.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.panorama_photosphere,
                size: 84, color: AppTheme.accent.withValues(alpha: 0.8)),
            const SizedBox(height: 20),
            const Text(
              'Welcome to 360Sphere!',
              style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start capturing amazing 360° photos and share them with the world.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
