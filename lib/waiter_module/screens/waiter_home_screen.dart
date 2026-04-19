import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter.dart';
import '../models/waiter_message.dart';
import '../services/waiter_controller.dart';
import 'waiter_messages_screen.dart';
import 'waiter_profile_screen.dart';
import 'waiter_tables_screen.dart';
import '../dialogs/incoming_call_banner.dart';

/// Shell for the waiter app — bottom nav plus the incoming-call banner.
class WaiterHomeScreen extends StatefulWidget {
  final WaiterController controller;

  const WaiterHomeScreen({super.key, required this.controller});

  @override
  State<WaiterHomeScreen> createState() => _WaiterHomeScreenState();
}

class _WaiterHomeScreenState extends State<WaiterHomeScreen> {
  int _tab = 0;
  StreamSubscription<WaiterMessage>? _callSub;

  @override
  void initState() {
    super.initState();
    _callSub = widget.controller.onIncomingCall.listen(_onIncomingCall);
    widget.controller.addListener(_onControllerChanged);
    widget.controller.messages.addListener(_onControllerChanged);
    widget.controller.roster.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _callSub?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.messages.removeListener(_onControllerChanged);
    widget.controller.roster.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onIncomingCall(WaiterMessage msg) {
    if (!mounted) return;
    showIncomingCallBanner(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.controller.session.self;
    final title = me == null || me.name.isEmpty
        ? translationService.t('waiter_module_title')
        : '${translationService.t('waiter_hi')}, ${me.name}';

    final pages = <Widget>[
      WaiterTablesScreen(controller: widget.controller),
      WaiterMessagesScreen(controller: widget.controller),
      WaiterProfileScreen(controller: widget.controller),
    ];

    return Scaffold(
      backgroundColor: context.appBg,
      appBar: AppBar(
        backgroundColor: context.appHeaderBg,
        foregroundColor: context.appText,
        elevation: 0,
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.appSurfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.users,
                        size: 14, color: context.appTextMuted),
                    const SizedBox(width: 4),
                    Text(
                      // Only real waiters, and only those currently online —
                      // an offline peer shouldn't inflate the "N waiters
                      // on shift" badge.
                      '${widget.controller.roster.all.where((w) => !w.isViewer && w.status != WaiterStatus.offline).length}',
                      style: TextStyle(
                        color: context.appTextMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(LucideIcons.layoutGrid),
            label: translationService.t('waiter_tab_tables'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.controller.messages.unreadCount > 0,
              label: Text('${widget.controller.messages.unreadCount}'),
              child: const Icon(LucideIcons.bell),
            ),
            label: translationService.t('waiter_tab_notifications'),
          ),
          NavigationDestination(
            icon: const Icon(LucideIcons.user),
            label: translationService.t('waiter_tab_me'),
          ),
        ],
      ),
    );
  }
}
