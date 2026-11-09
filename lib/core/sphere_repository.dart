import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// File-backed store for captured photospheres.
///
/// Layout inside the application documents directory:
/// ```
/// spheres/
///   index.json          — list of Photosphere metadata
///   <id>.jpg            — equirectangular JPEG, 2:1 aspect
///   thumbs/<id>.jpg     — small preview for the gallery grid
/// ```
class SphereRepository {
  SphereRepository(this._appDocs);

  final Directory _appDocs;

  Directory get spheresDir {
    final d = Directory('${_appDocs.path}/spheres');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Directory get thumbsDir {
    final d = Directory('${spheresDir.path}/thumbs');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  File get _indexFile => File('${spheresDir.path}/index.json');

  Future<List<Photosphere>> list() async {
    if (!_indexFile.existsSync()) return [];
    try {
      final raw = jsonDecode(await _indexFile.readAsString()) as List<dynamic>;
      final spheres = raw
          .map((e) => Photosphere.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return spheres;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<Photosphere> spheres) => _indexFile
      .writeAsString(const JsonEncoder.withIndent('  ').convert(spheres));

  Future<Photosphere> save({
    required String name,
    required Uint8List jpeg,
    required Uint8List thumb,
    required int width,
    required int height,
    required int frameCount,
    required bool watermarked,
    String description = '',
    GeoPose? geoLocation,
  }) async {
    final id = 'sp_${DateTime.now().millisecondsSinceEpoch}_${_randSuffix()}';
    final imageFile = File('${spheresDir.path}/$id.jpg');
    final thumbFile = File('${thumbsDir.path}/$id.jpg');
    await imageFile.writeAsBytes(jpeg, flush: true);
    await thumbFile.writeAsBytes(thumb, flush: true);

    final sphere = Photosphere(
      id: id,
      name: name,
      createdAt: DateTime.now(),
      imageFileName: '$id.jpg',
      width: width,
      height: height,
      frameCount: frameCount,
      description: description,
      watermarked: watermarked,
      geoLocation: geoLocation,
    );

    final all = await list();
    all.insert(0, sphere);
    await _writeIndex(all);
    return sphere;
  }

  String imagePath(Photosphere sphere) =>
      '${spheresDir.path}/${sphere.imageFileName}';
  String thumbPath(Photosphere sphere) =>
      '${thumbsDir.path}/${sphere.imageFileName}';

  Future<void> rename(Photosphere sphere, String newName) async {
    sphere.name = newName;
    final all = await list();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == sphere.id) all[i] = sphere;
    }
    await _writeIndex(all);
  }

  /// Persist name + description edits (the original's PhotoNameScreen
  /// saves both fields together).
  Future<void> updateDetails(
    Photosphere sphere, {
    required String name,
    required String description,
  }) async {
    sphere.name = name;
    sphere.description = description;
    final all = await list();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == sphere.id) all[i] = sphere;
    }
    await _writeIndex(all);
  }

  Future<void> update(Photosphere sphere) => rename(sphere, sphere.name);

  Future<void> delete(Photosphere sphere) async {
    final all = (await list()).where((s) => s.id != sphere.id).toList();
    await _writeIndex(all);
    final img = File(imagePath(sphere));
    final thumb = File(thumbPath(sphere));
    if (img.existsSync()) await img.delete();
    if (thumb.existsSync()) await thumb.delete();
  }

  static String _randSuffix() {
    final r = DateTime.now().microsecondsSinceEpoch % 0xFFFF;
    return r.toRadixString(36).padLeft(3, '0');
  }

  static Future<SphereRepository> create() async =>
      SphereRepository(await getApplicationDocumentsDirectory());
}
