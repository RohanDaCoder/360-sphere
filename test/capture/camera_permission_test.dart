import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:sphere360/capture/camera_permission.dart';

void main() {
  group('CameraPermissionGate', () {
    test('already granted → granted without requesting', () async {
      var requests = 0;
      final gate = CameraPermissionGate(
        checkStatus: () async => PermissionStatus.granted,
        request: () async {
          requests++;
          return PermissionStatus.granted;
        },
      );

      expect(await gate.ensure(), CameraPermissionOutcome.granted);
      expect(requests, 0, reason: 'no dialog needed once granted');
    });

    test('limited grant counts as granted', () async {
      final gate = CameraPermissionGate(
        checkStatus: () async => PermissionStatus.limited,
        request: () async => PermissionStatus.limited,
      );

      expect(await gate.ensure(), CameraPermissionOutcome.granted);
    });

    test('notDetermined → request → granted', () async {
      var requests = 0;
      final gate = CameraPermissionGate(
        checkStatus: () async => PermissionStatus.denied,
        request: () async {
          requests++;
          return PermissionStatus.granted;
        },
      );

      expect(await gate.ensure(), CameraPermissionOutcome.granted);
      expect(requests, 1);
    });

    test('request denied → denied (Retry can ask again)', () async {
      final gate = CameraPermissionGate(
        checkStatus: () async => PermissionStatus.denied,
        request: () async => PermissionStatus.denied,
      );

      expect(await gate.ensure(), CameraPermissionOutcome.denied);
    });

    test('request permanently denied → permanentlyDenied', () async {
      final gate = CameraPermissionGate(
        checkStatus: () async => PermissionStatus.denied,
        request: () async => PermissionStatus.permanentlyDenied,
      );

      expect(await gate.ensure(), CameraPermissionOutcome.permanentlyDenied);
    });

    test('status already permanentlyDenied → no request attempt', () async {
      var requests = 0;
      final gate = CameraPermissionGate(
        checkStatus: () async => PermissionStatus.permanentlyDenied,
        request: () async {
          requests++;
          return PermissionStatus.permanentlyDenied;
        },
      );

      // The OS would not show a dialog anymore; the gate must not try.
      expect(await gate.ensure(), CameraPermissionOutcome.permanentlyDenied);
      expect(requests, 0);
    });
  });
}
