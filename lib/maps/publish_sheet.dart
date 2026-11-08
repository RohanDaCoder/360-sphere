import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/theme.dart';
import 'google_auth_service.dart';
import 'streetview_publish_service.dart';

/// Bottom sheet that publishes a photosphere to Google Street View / Maps.
Future<void> showPublishSheet(
  BuildContext context, {
  required String imagePath,
  required void Function(String photoId) onPublished,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PublishSheet(
      imagePath: imagePath,
      onPublished: onPublished,
    ),
  );
}

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.imagePath, required this.onPublished});

  final String imagePath;
  final void Function(String photoId) onPublished;

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

enum _PublishPhase { form, signingIn, uploading, publishing, done, error }

class _PublishSheetState extends State<_PublishSheet> {
  final GoogleAuthService _auth = GoogleAuthService();
  late final StreetViewPublishService _api;

  final TextEditingController _lat = TextEditingController();
  final TextEditingController _lng = TextEditingController();
  double _heading = 0;

  _PublishPhase _phase = _PublishPhase.form;
  String? _error;
  String? _photoId;

  @override
  void initState() {
    super.initState();
    _api = StreetViewPublishService(
      accessTokenProvider: () async => _auth.accessToken(),
    );
    _fillLocation();
  }

  Future<void> _fillLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      _lat.text = pos.latitude.toStringAsFixed(6);
      _lng.text = pos.longitude.toStringAsFixed(6);
      if (mounted) setState(() {});
    } catch (_) {
      // leave fields empty for manual entry
    }
  }

  Future<void> _publish() async {
    final lat = double.tryParse(_lat.text);
    final lng = double.tryParse(_lng.text);
    if (lat == null || lng == null) {
      setState(() => _error = 'Enter valid latitude / longitude.');
      return;
    }
    setState(() {
      _phase = _PublishPhase.signingIn;
      _error = null;
    });
    try {
      final account = await _auth.signIn();
      if (account == null) {
        setState(() {
          _phase = _PublishPhase.error;
          _error = 'Sign-in cancelled.';
        });
        return;
      }

      setState(() => _phase = _PublishPhase.uploading);
      final bytes = await File(widget.imagePath).readAsBytes();

      final uploadUrl = await _api.startUpload();
      await _api.uploadBytes(uploadUrl, bytes);

      setState(() => _phase = _PublishPhase.publishing);
      final photoId = await _api.createPhoto(
        uploadUrl: uploadUrl,
        latitude: lat,
        longitude: lng,
        headingDeg: _heading,
      );

      setState(() => _phase = _PublishPhase.done);
      widget.onPublished(photoId);
    } on GoogleAuthException catch (e) {
      setState(() {
        _phase = _PublishPhase.error;
        _error = e.message;
      });
    } on StreetViewException catch (e) {
      setState(() {
        _phase = _PublishPhase.error;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _phase = _PublishPhase.error;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _api.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.public, color: AppTheme.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Publish to Google Maps',
                  style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Your 360° photo will be uploaded to Google Street View. '
            'Published photos can appear on Google Maps for everyone.',
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          if (_phase == _PublishPhase.form || _phase == _PublishPhase.error) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    keyboardType:
                        const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    keyboardType:
                        const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                  ),
                ),
                IconButton(
                  onPressed: _fillLocation,
                  icon: const Icon(Icons.my_location),
                  tooltip: 'Use current location',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Heading'),
                Expanded(
                  child: Slider(
                    value: _heading,
                    max: 360,
                    divisions: 72,
                    label: '${_heading.round()}°',
                    onChanged: (v) => setState(() => _heading = v),
                  ),
                ),
                Text('${_heading.round()}°'),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style:
                    const TextStyle(color: AppTheme.warn, fontSize: 12, height: 1.4),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _publish,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Sign in & publish'),
            ),
          ] else ...[
            const SizedBox(height: 12),
            _PhaseRow(phase: _phase),
            if (_phase == _PublishPhase.done) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.ok.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Published!',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: AppTheme.ok)),
                    const SizedBox(height: 4),
                    Text('Street View photo id: $_photoId',
                        style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 4),
                    const Text(
                      'It may take some time before the photo appears on Google Maps.',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({required this.phase});

  final _PublishPhase phase;

  @override
  Widget build(BuildContext context) {
    Widget step(String label, _PublishPhase value) {
      final active = phase == value;
      final done = phase.index > value.index || phase == _PublishPhase.done;
      return Row(
        children: [
          if (done)
            const Icon(Icons.check_circle, size: 18, color: AppTheme.ok)
          else if (active)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppTheme.accent),
            )
          else
            const Icon(Icons.circle_outlined, size: 18, color: Colors.white30),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                color: active || done ? Colors.white : Colors.white38,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              )),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        step('Signing in with Google', _PublishPhase.signingIn),
        const SizedBox(height: 6),
        step('Uploading 360° photo', _PublishPhase.uploading),
        const SizedBox(height: 6),
        step('Publishing to Street View', _PublishPhase.publishing),
      ],
    );
  }
}
