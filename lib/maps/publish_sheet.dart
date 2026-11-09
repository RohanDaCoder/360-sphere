import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'google_auth_service.dart';
import 'streetview_errors.dart';
import 'streetview_publish_service.dart';

/// Bottom sheet that publishes a photosphere to Google Street View / Maps.
///
/// [geoLocation] / [captureTime] come from the photo's capture session (the
/// original uploads with its stored `geo_location` and capture timestamp);
/// they prefill the pose fields, which stay editable.
Future<void> showPublishSheet(
  BuildContext context, {
  required String imagePath,
  GeoPose? geoLocation,
  DateTime? captureTime,
  required void Function(String photoId, String? shareLink) onPublished,
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
      geoLocation: geoLocation,
      captureTime: captureTime,
      onPublished: onPublished,
    ),
  );
}

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({
    required this.imagePath,
    required this.onPublished,
    this.geoLocation,
    this.captureTime,
  });

  final String imagePath;
  final GeoPose? geoLocation;
  final DateTime? captureTime;
  final void Function(String photoId, String? shareLink) onPublished;

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
  String? _errorTitle;
  String? _error;
  String? _photoId;
  String? _shareLink;

  @override
  void initState() {
    super.initState();
    _api = StreetViewPublishService(
      accessTokenProvider: () async => _auth.accessToken(),
    );
    final geo = widget.geoLocation;
    if (geo != null) {
      // Prefill from the position recorded at capture time (the original
      // publishes with its stored geo_location, no re-fix needed).
      _lat.text = geo.latitude.toStringAsFixed(6);
      _lng.text = geo.longitude.toStringAsFixed(6);
      _heading = geo.heading?.clamp(0, 360) ?? 0;
    } else {
      _fillLocation();
    }
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

  /// Open Google's `shareLink` for the published photo (the original's
  /// viewer exposes the same link behind its Google Maps button).
  Future<void> _openShareLink() async {
    final link = _shareLink;
    if (link == null) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link')),
        );
      }
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
      _errorTitle = null;
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

      // Pre-flight: Google rejects photos without 360° metadata with its
      // "Not a 360° Photo" error — catch it before uploading (the original
      // app maps the same server response to an alert dialog).
      final preflight = preflightCheck(bytes);
      if (preflight != null) {
        setState(() {
          _phase = _PublishPhase.error;
          _errorTitle = preflight.title;
          _error = preflight.message;
        });
        return;
      }

      final uploadUrl = await _api.startUpload();
      await _api.uploadBytes(uploadUrl, bytes);

      setState(() => _phase = _PublishPhase.publishing);
      final photo = await _api.createPhoto(
        uploadUrl: uploadUrl,
        latitude: lat,
        longitude: lng,
        headingDeg: _heading,
        captureTime: widget.captureTime,
      );

      setState(() {
        _phase = _PublishPhase.done;
        _photoId = photo.id;
        _shareLink = photo.shareLink;
      });
      widget.onPublished(photo.id, photo.shareLink);
    } on GoogleAuthException catch (e) {
      setState(() {
        _phase = _PublishPhase.error;
        _error = e.message;
      });
    } catch (e) {
      // Classify like the original's alert mapping (Location Required /
      // Photo Too Large / Already Uploaded / Connection Error / Not a 360°
      // Photo / Token Expired / Permission Required / Upload Failed).
      final sv = classifyStreetViewError(e);
      setState(() {
        _phase = _PublishPhase.error;
        _errorTitle = sv.title;
        _error = sv.message;
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
          if (_phase == _PublishPhase.form ||
              _phase == _PublishPhase.error) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
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
              if (_errorTitle != null)
                Text(
                  _errorTitle!,
                  style: const TextStyle(
                      color: AppTheme.warn,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              Text(
                _error!,
                style: const TextStyle(
                    color: AppTheme.warn, fontSize: 12, height: 1.4),
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
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                    if (_shareLink != null) ...[
                      const SizedBox(height: 8),
                      Builder(builder: (context) {
                        final link = _shareLink!;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _openShareLink,
                              icon: const Icon(Icons.map, size: 18),
                              label: const Text('Open in Google Maps'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: link));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Link copied')),
                                );
                              },
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('Copy link'),
                            ),
                          ],
                        );
                      }),
                    ],
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
