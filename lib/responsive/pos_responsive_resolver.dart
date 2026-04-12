import 'package:flutter/material.dart';
import 'pos_device_config.dart';

/// Resolves the active POS layout profile using MediaQuery and orientation.
class PosResponsiveResolver {
  static PosDeviceConfig resolve(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortestSide = media.size.shortestSide;
    final longestSide = media.size.longestSide;
    final orientation = media.orientation;

    if (shortestSide >= 600 && longestSide >= 900 && orientation == Orientation.landscape) {
      return PosDeviceConfig.d3Pro;
    }

    if (shortestSide < 400 && orientation == Orientation.portrait) {
      return PosDeviceConfig.v2sPlus;
    }

    if (shortestSide >= 400 && shortestSide < 600 && orientation == Orientation.portrait) {
      return PosDeviceConfig.d3Mini;
    }

    return orientation == Orientation.landscape
        ? PosDeviceConfig.d3Pro
        : PosDeviceConfig.d3Mini;
  }
}
