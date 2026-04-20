import 'package:get_it/get_it.dart';
import 'package:hermosa_pos/services/api/auth_service.dart';
import 'package:hermosa_pos/services/api/order_service.dart';
import 'package:hermosa_pos/services/api/product_service.dart';
import 'package:hermosa_pos/services/api/report_service.dart';
import 'package:hermosa_pos/services/api/table_service.dart';
import 'package:hermosa_pos/services/api/profile_service.dart';
import 'package:hermosa_pos/services/api/filter_service.dart';
import 'package:hermosa_pos/services/api/branch_service.dart';
import 'package:hermosa_pos/services/api/customer_service.dart';
import 'package:hermosa_pos/services/api/device_service.dart';
import 'package:hermosa_pos/services/api/salon_employee_service.dart';
import 'package:hermosa_pos/services/printer_service.dart';
import 'package:hermosa_pos/services/printer_role_registry.dart';
import 'package:hermosa_pos/services/category_printer_route_registry.dart';
import 'package:hermosa_pos/services/kitchen_printer_route_registry.dart';
import 'package:hermosa_pos/services/print_orchestrator_service.dart';
import 'package:hermosa_pos/services/print_audit_service.dart';
import 'package:hermosa_pos/services/display_app_service.dart';
import 'package:hermosa_pos/services/presentation_service.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/cashier_sound_service.dart';
import 'package:hermosa_pos/services/kds_meal_availability_service.dart';
import 'package:hermosa_pos/services/invoice_html_pdf_service.dart';
import 'package:hermosa_pos/services/kitchen_html_pdf_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/offline_pos_database.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/services/offline/sync_service.dart';
import 'package:hermosa_pos/services/api/sync_api_service.dart';
import 'package:hermosa_pos/customer_display/nearpay/nearpay_service.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_billing_service.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_cart_store.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_config_store.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_controller.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_kitchen_bridge.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_message_store.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_notification_service.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_order_outbox.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_pickup_store.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_roster_service.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_session_service.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_table_registry.dart';
import 'package:hermosa_pos/services/cashier_mesh_bootstrap.dart';

final getIt = GetIt.instance;

void setupLocator() {
  // Allow reassignment on hot restart
  getIt.allowReassignment = true;

  void registerIfNeeded<T extends Object>(T Function() factory) {
    if (!getIt.isRegistered<T>()) {
      getIt.registerLazySingleton<T>(factory);
    }
  }

  // Common Services
  registerIfNeeded<CacheService>(() => CacheService());

  // Offline Services
  registerIfNeeded<OfflineDatabaseService>(() => OfflineDatabaseService());
  registerIfNeeded<OfflinePosDatabase>(() => OfflinePosDatabase());
  registerIfNeeded<ConnectivityService>(() => ConnectivityService());
  registerIfNeeded<SyncService>(() => SyncService());
  registerIfNeeded<SyncApiService>(() => SyncApiService());

  // API Services
  registerIfNeeded<AuthService>(() => AuthService());
  registerIfNeeded<ProductService>(() => ProductService());
  registerIfNeeded<OrderService>(() => OrderService());
  registerIfNeeded<TableService>(() => TableService());
  registerIfNeeded<ReportService>(() => ReportService());
  registerIfNeeded<ProfileService>(() => ProfileService());
  registerIfNeeded<FilterService>(() => FilterService());
  registerIfNeeded<BranchService>(() => BranchService());
  registerIfNeeded<CustomerService>(() => CustomerService());
  registerIfNeeded<DeviceService>(() => DeviceService());
  registerIfNeeded<SalonEmployeeService>(() => SalonEmployeeService());
  registerIfNeeded<InvoiceHtmlPdfService>(() => InvoiceHtmlPdfService());
  registerIfNeeded<KitchenHtmlPdfService>(() => KitchenHtmlPdfService());

  // Hardware Services
  registerIfNeeded<PrinterService>(() => PrinterService());
  registerIfNeeded<PrinterRoleRegistry>(() => PrinterRoleRegistry());
  registerIfNeeded<CategoryPrinterRouteRegistry>(
    () => CategoryPrinterRouteRegistry(),
  );
  registerIfNeeded<KitchenPrinterRouteRegistry>(
    () => KitchenPrinterRouteRegistry(),
  );
  registerIfNeeded<PrintOrchestratorService>(
    () => PrintOrchestratorService(
      getIt<PrinterService>(),
      getIt<PrinterRoleRegistry>(),
    ),
  );

  // Print Audit
  registerIfNeeded<PrintAuditService>(() => PrintAuditService());

  // Display App Service
  registerIfNeeded<DisplayAppService>(() => DisplayAppService());

  // Presentation Service (dual-screen devices like Sunmi D2s)
  registerIfNeeded<PresentationService>(() => PresentationService());

  // Sound service
  registerIfNeeded<CashierSoundService>(() => CashierSoundService());
  registerIfNeeded<KdsMealAvailabilityService>(
      () => KdsMealAvailabilityService());

  // NearPay Service (local SDK — no WebSocket/Display App dependency).
  // Matches the reference implementation from display_app/lib/services/nearpay_service.dart
  registerIfNeeded<NearPayService>(() => NearPayService());

  // ─── Waiter module ───
  registerIfNeeded<WaiterSessionService>(() => WaiterSessionService());
  registerIfNeeded<WaiterRosterService>(() => WaiterRosterService());
  registerIfNeeded<WaiterMessageStore>(() => WaiterMessageStore());
  registerIfNeeded<WaiterNotificationService>(() => WaiterNotificationService());
  registerIfNeeded<WaiterCartStore>(() => WaiterCartStore());
  registerIfNeeded<WaiterTableRegistry>(() => WaiterTableRegistry());
  registerIfNeeded<WaiterConfigStore>(() => WaiterConfigStore());
  registerIfNeeded<WaiterPickupStore>(() => WaiterPickupStore());
  registerIfNeeded<WaiterKitchenBridge>(
      () => WaiterKitchenBridge(getIt<DisplayAppService>()));
  registerIfNeeded<WaiterOrderOutbox>(() => WaiterOrderOutbox(
        bridge: getIt<WaiterKitchenBridge>(),
        connectivity: getIt<ConnectivityService>(),
      ));
  registerIfNeeded<WaiterController>(() => WaiterController(
        session: getIt<WaiterSessionService>(),
        roster: getIt<WaiterRosterService>(),
        messages: getIt<WaiterMessageStore>(),
        notifications: getIt<WaiterNotificationService>(),
        tableRegistry: getIt<WaiterTableRegistry>(),
        configStore: getIt<WaiterConfigStore>(),
        pickupStore: getIt<WaiterPickupStore>(),
      ));
  registerIfNeeded<WaiterBillingService>(() => WaiterBillingService());
  registerIfNeeded<CashierMeshBootstrap>(() => CashierMeshBootstrap(
        controller: getIt<WaiterController>(),
        configStore: getIt<WaiterConfigStore>(),
      ));
}
