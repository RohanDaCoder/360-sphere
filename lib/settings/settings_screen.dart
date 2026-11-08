import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../core/theme.dart';

/// Capture & viewer preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('Capture'),
          ListTile(
            title: const Text('Output resolution'),
            subtitle: Text('${s.equirectWidth} × ${s.equirectHeight} px '
                '(${s.equirectWidth >= 4096 ? 'Street View ready' : 'smaller, faster'})'),
            trailing: DropdownButton<int>(
              value: s.equirectWidth,
              items: const [
                DropdownMenuItem(value: 2048, child: Text('2048')),
                DropdownMenuItem(value: 4096, child: Text('4096')),
              ],
              onChanged: (v) => controller
                  .update(controller.settings.copyWith(equirectWidth: v)),
            ),
          ),
          ListTile(
            title: const Text('Camera field of view'),
            subtitle: Text(
                '${s.cameraFovDegrees.toStringAsFixed(0)}° — calibrate if seams misalign. For the fisheye mode, set the lens’ diagonal FOV (e.g. 180°).'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: s.cameraFovDegrees,
                min: 40,
                max: 180,
                divisions: 140,
                label: '${s.cameraFovDegrees.round()}°',
                onChanged: (v) => controller
                    .update(controller.settings.copyWith(cameraFovDegrees: v)),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Compass yaw assist'),
            subtitle: const Text(
                'Use the magnetometer to bound gyro yaw drift. Disable near strong magnetic fields.',
                style: TextStyle(fontSize: 12)),
            value: s.compassAssist,
            onChanged: (v) => controller
                .update(controller.settings.copyWith(compassAssist: v)),
          ),
          SwitchListTile(
            title: const Text('Capture floor dot'),
            subtitle: const Text(
                'Include the floor target in photosphere layouts (point the camera straight down).',
                style: TextStyle(fontSize: 12)),
            value: s.includeFloorCapture,
            onChanged: (v) => controller
                .update(controller.settings.copyWith(includeFloorCapture: v)),
          ),
          const _SectionHeader('Output'),
          SwitchListTile(
            title: const Text('Watermark'),
            subtitle: Text('Stamp "${s.watermarkLabel}" on saved photos',
                style: const TextStyle(fontSize: 12)),
            value: s.watermark,
            onChanged: (v) =>
                controller.update(controller.settings.copyWith(watermark: v)),
          ),
          ListTile(
            title: const Text('Watermark author'),
            subtitle: const Text(
                'Shown as "Created in 360Sphere by {author}". Leave empty for the plain signature.',
                style: TextStyle(fontSize: 12)),
            trailing: SizedBox(
              width: 150,
              child: TextField(
                controller: TextEditingController(text: s.authorName)
                  ..selection = TextSelection.fromPosition(
                      TextPosition(offset: s.authorName.length)),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'e.g. Rohan',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => controller
                    .update(controller.settings.copyWith(authorName: v)),
              ),
            ),
          ),
          const _SectionHeader('Troubleshooting'),
          ListTile(
            title: const Text('Frame rotation fix'),
            subtitle: const Text(
                'If stitched frames appear rotated 90°, flip this and retry.',
                style: TextStyle(fontSize: 12)),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: -1, label: Text('⟲90°')),
                ButtonSegment(value: 0, label: Text('Auto')),
                ButtonSegment(value: 1, label: Text('⟳90°')),
              ],
              selected: {s.frameRotationFix},
              onSelectionChanged: (sel) => controller.update(
                  controller.settings.copyWith(frameRotationFix: sel.first)),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '360Sphere — a clean-room Flutter recreation of the 360 Photo Cam '
            'app architecture. Analysis documentation lives in docs/.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4, left: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppTheme.accent,
        ),
      ),
    );
  }
}
