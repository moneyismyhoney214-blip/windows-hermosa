import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/offline/connectivity_service.dart';

class ConnectivityStatusIndicator extends StatefulWidget {
  final double iconSize;
  final EdgeInsetsGeometry padding;

  const ConnectivityStatusIndicator({
    super.key,
    this.iconSize = 20,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  @override
  State<ConnectivityStatusIndicator> createState() =>
      _ConnectivityStatusIndicatorState();
}

class _ConnectivityStatusIndicatorState
    extends State<ConnectivityStatusIndicator> {
  final ConnectivityService _service = ConnectivityService();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final online = _service.isOnline;
    return Padding(
      padding: widget.padding,
      child: Icon(
        online ? LucideIcons.wifi : LucideIcons.wifiOff,
        size: widget.iconSize,
        color: online ? Colors.green : Colors.red,
      ),
    );
  }
}
