import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/services/display_app_service.dart';
import 'package:hermosa_pos/utils/display_device_selection.dart';

DeviceConfig _device({
  required String id,
  required String ip,
  required String type,
  String port = '8080',
}) {
  return DeviceConfig(
    id: id,
    name: id,
    ip: ip,
    port: port,
    type: type,
    model: 'display',
  );
}

DisplayMode _modeForDevice(DeviceConfig device) {
  final normalized = device.type.trim().toLowerCase();
  if (device.id.startsWith('kitchen:')) {
    return normalized == 'cds' || normalized == 'customer_display'
        ? DisplayMode.cds
        : DisplayMode.kds;
  }
  if (normalized == 'cds' ||
      normalized == 'customer_display' ||
      normalized == 'order_viewer') {
    return DisplayMode.cds;
  }
  return DisplayMode.kds;
}

void main() {
  group('display device selection', () {
    test('does not treat KDS devices as CDS fallback candidates', () {
      final selected = pickPreferredCdsDisplayDevice(
        [
          _device(id: 'kitchen:1', ip: '192.168.1.10', type: 'kds'),
        ],
        modeForDevice: _modeForDevice,
        preferredIp: '192.168.1.10',
        preferredPort: 8080,
      );

      expect(selected, isNull);
    });

    test('picks a real CDS device even when the connected display is KDS', () {
      final selected = pickPreferredCdsDisplayDevice(
        [
          _device(id: 'kitchen:1', ip: '192.168.1.10', type: 'kds'),
          _device(id: 'cds:1', ip: '192.168.1.20', type: 'customer_display'),
        ],
        modeForDevice: _modeForDevice,
        preferredIp: '192.168.1.10',
        preferredPort: 8080,
      );

      expect(selected, isNotNull);
      expect(selected!.id, 'cds:1');
    });

    test('does not reuse a live KDS session for CDS auto-connect', () {
      final canReuse = canReuseCurrentConnectionForCdsAutoConnect(
        currentMode: DisplayMode.kds,
        connectedDevice: _device(
          id: 'kitchen:1',
          ip: '192.168.1.10',
          type: 'kds',
        ),
        modeForDevice: _modeForDevice,
      );

      expect(canReuse, isFalse);
    });

    test('allows reusing an already assigned CDS session', () {
      final canReuse = canReuseCurrentConnectionForCdsAutoConnect(
        currentMode: DisplayMode.cds,
        connectedDevice: _device(
          id: 'cds:1',
          ip: '192.168.1.20',
          type: 'customer_display',
        ),
        modeForDevice: _modeForDevice,
      );

      expect(canReuse, isTrue);
    });

    test('matches configured display using ip and port', () {
      final matched = findConfiguredDisplayDevice(
        [
          _device(id: 'kitchen:1', ip: '192.168.1.10', type: 'kds'),
          _device(
            id: 'cds:1',
            ip: '192.168.1.10',
            type: 'customer_display',
            port: '8081',
          ),
        ],
        isDisplayDevice: (_) => true,
        ip: '192.168.1.10',
        port: 8081,
      );

      expect(matched, isNotNull);
      expect(matched!.id, 'cds:1');
    });

    test('requires reconnect when the connected display is assigned to KDS',
        () {
      final needsReconnect = requiresDedicatedCdsReconnect(
        _device(id: 'kitchen:1', ip: '192.168.1.10', type: 'kds'),
        modeForDevice: _modeForDevice,
      );
      final keepsCurrentConnection = requiresDedicatedCdsReconnect(
        _device(id: 'cds:1', ip: '192.168.1.20', type: 'customer_display'),
        modeForDevice: _modeForDevice,
      );

      expect(needsReconnect, isTrue);
      expect(keepsCurrentConnection, isFalse);
    });
  });
}
