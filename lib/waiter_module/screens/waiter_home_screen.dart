import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/api/api_constants.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../../services/waitlist_service.dart';
import '../../services/whatsapp_service.dart';
import '../../widgets/waitlist_sheet.dart';
import '../dialogs/incoming_call_banner.dart';
import '../dialogs/incoming_pickup_banner.dart';
import '../models/table_pickup_request.dart';
import '../models/waiter_message.dart';
import '../services/waiter_controller.dart';
import '../theme/waiter_design.dart';
import 'waiter_messages_screen.dart';
import 'waiter_profile_screen.dart';
import 'waiter_tables_screen.dart';

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
  StreamSubscription<TablePickupRequest>? _pickupSub;
  StreamSubscription<String>? _openTableSub;

  @override
  void initState() {
    super.initState();
    _callSub = widget.controller.onIncomingCall.listen(_onIncomingCall);
    _pickupSub = widget.controller.onPickupRequest.listen(_onPickupRequest);
    // Ensure tables tab is selected so the order screen pushes over the right view.
    _openTableSub = widget.controller.onOpenTableRequest.listen((_) {
      if (mounted && _tab != 0) setState(() => _tab = 0);
    });
    widget.controller.addListener(_onControllerChanged);
    widget.controller.messages.addListener(_onControllerChanged);
    widget.controller.roster.addListener(_onControllerChanged);
    widget.controller.pickupStore.addListener(_onControllerChanged);
    // Lazy-boot waitlist + message bridge so badge counts are live on landing.
    unawaited(waitlistService.initialize());
    unawaited(whatsAppService.initialize());
    waitlistService.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _pickupSub?.cancel();
    _openTableSub?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.messages.removeListener(_onControllerChanged);
    widget.controller.roster.removeListener(_onControllerChanged);
    widget.controller.pickupStore.removeListener(_onControllerChanged);
    waitlistService.removeListener(_onControllerChanged);
    super.dispose();
  }

  Future<void> _openWaitlist() => WaitlistSheet.show(context);

  void _onControllerChanged() {
    if (!mounted) return;
    // Auto-mark as read while user is on the notifications tab.
    if (_tab == 1 && widget.controller.messages.unreadCount > 0) {
      widget.controller.messages.markAllRead();
    }
    setState(() {});
  }

  void _onIncomingCall(WaiterMessage msg) {
    if (!mounted) return;
    showIncomingCallBanner(context, msg);
  }

  void _onPickupRequest(TablePickupRequest req) {
    if (!mounted) return;
    // Cashier viewers already see the pending card; skip the banner.
    if (widget.controller.session.self?.isViewer ?? false) return;
    // A waiter mid-order isn't interrupted; request still lands in the notifications feed.
    if (widget.controller.isTakingOrderNow) return;
    showIncomingPickupBanner(context, req, widget.controller);
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

    final waitlistCount = waitlistService.activeCount;

    return Scaffold(
      backgroundColor: context.appBg,
      appBar: AppBar(
        backgroundColor: context.appHeaderBg,
        foregroundColor: context.appText,
        elevation: 0,
        title: Text(title),
        actions: [
          // Tables-tab only; gated on branch having waiters or WhatsApp.
          if (_tab == 0 &&
              (ApiConstants.whatsappEnabled || ApiConstants.haveWaiters))
            IconButton(
              tooltip: translationService.t('waitlist_tooltip'),
              onPressed: _openWaitlist,
              icon: Badge(
                isLabelVisible: waitlistCount > 0,
                label: Text('$waitlistCount'),
                backgroundColor: const Color(0xFFDC2626),
                child: const Icon(LucideIcons.clock),
              ),
            ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (i != _tab) {
            unawaited(WaiterHaptics.tick());
          }
          if (i == 1) {
            widget.controller.messages.markAllRead();
          }
          setState(() => _tab = i);
        },
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
