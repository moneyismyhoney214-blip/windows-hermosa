import 'package:flutter/material.dart';

/// Holds POS layout tokens for each supported Sunmi device profile.
@immutable
class PosDeviceConfig {
  final int gridColumns;
  final double headerHeight;
  final double cardWidth;
  final double cardHeight;
  final double buttonHeight;
  final double fontTitle;
  final double fontButton;

  const PosDeviceConfig({
    required this.gridColumns,
    required this.headerHeight,
    required this.cardWidth,
    required this.cardHeight,
    required this.buttonHeight,
    required this.fontTitle,
    required this.fontButton,
  });

  static const PosDeviceConfig d3Pro = PosDeviceConfig(
    gridColumns: 5,
    headerHeight: 64,
    cardWidth: 200,
    cardHeight: 280,
    buttonHeight: 72,
    fontTitle: 18,
    fontButton: 20,
  );

  static const PosDeviceConfig t2 = PosDeviceConfig(
    gridColumns: 5,
    headerHeight: 64,
    cardWidth: 200,
    cardHeight: 280,
    buttonHeight: 72,
    fontTitle: 18,
    fontButton: 20,
  );

  static const PosDeviceConfig v2sPlus = PosDeviceConfig(
    gridColumns: 2,
    headerHeight: 48,
    cardWidth: 160,
    cardHeight: 300,
    buttonHeight: 56,
    fontTitle: 14,
    fontButton: 16,
  );

  static const PosDeviceConfig d3Mini = PosDeviceConfig(
    gridColumns: 3,
    headerHeight: 56,
    cardWidth: 180,
    cardHeight: 230,
    buttonHeight: 64,
    fontTitle: 16,
    fontButton: 18,
  );
}
