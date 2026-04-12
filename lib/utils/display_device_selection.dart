import '../models.dart';
import '../services/display_app_service.dart';

bool matchesDisplayEndpoint(
  DeviceConfig device, {
  String? ip,
  int? port,
}) {
  final normalizedIp = ip?.trim();
  if (normalizedIp == null || normalizedIp.isEmpty) return false;
  if (device.ip.trim() != normalizedIp) return false;
  if (port == null) return true;
  return (int.tryParse(device.port) ?? 8080) == port;
}

DeviceConfig? findConfiguredDisplayDevice(
  Iterable<DeviceConfig> devices, {
  required bool Function(DeviceConfig device) isDisplayDevice,
  String? ip,
  int? port,
}) {
  final normalizedIp = ip?.trim();
  if (normalizedIp == null || normalizedIp.isEmpty) return null;

  for (final device in devices) {
    if (!isDisplayDevice(device)) continue;
    if (matchesDisplayEndpoint(device, ip: normalizedIp, port: port)) {
      return device;
    }
  }
  return null;
}

DeviceConfig? pickPreferredCdsDisplayDevice(
  Iterable<DeviceConfig> devices, {
  required DisplayMode Function(DeviceConfig device) modeForDevice,
  String? preferredIp,
  int? preferredPort,
}) {
  final candidates = devices
      .where(
        (device) =>
            device.ip.trim().isNotEmpty &&
            modeForDevice(device) == DisplayMode.cds,
      )
      .toList(growable: false);
  if (candidates.isEmpty) return null;

  for (final device in candidates) {
    if (matchesDisplayEndpoint(
      device,
      ip: preferredIp,
      port: preferredPort,
    )) {
      return device;
    }
  }

  return candidates.first;
}

bool canReuseCurrentConnectionForCdsAutoConnect({
  required DisplayMode currentMode,
  required DisplayMode Function(DeviceConfig device) modeForDevice,
  DeviceConfig? connectedDevice,
}) {
  if (currentMode == DisplayMode.cds) return true;
  if (currentMode == DisplayMode.kds) return false;
  return connectedDevice != null &&
      modeForDevice(connectedDevice) == DisplayMode.cds;
}

bool requiresDedicatedCdsReconnect(
  DeviceConfig? connectedDevice, {
  required DisplayMode Function(DeviceConfig device) modeForDevice,
}) {
  return connectedDevice != null &&
      modeForDevice(connectedDevice) != DisplayMode.cds;
}
