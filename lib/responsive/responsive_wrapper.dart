import 'package:flutter/material.dart';
import 'pos_device_config.dart';
import 'pos_responsive_resolver.dart';

/// Rebuilds on orientation changes and exposes the resolved POS config.
class ResponsiveWrapper extends StatelessWidget {
  final Widget Function(BuildContext context, PosDeviceConfig config) builder;

  const ResponsiveWrapper({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, _) {
        final config = PosResponsiveResolver.resolve(context);
        return builder(context, config);
      },
    );
  }
}
