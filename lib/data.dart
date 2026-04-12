import 'package:lucide_icons/lucide_icons.dart';
import 'models.dart';

// Navigation items - used for UI structure
const List<NavItem> navItems = [
  NavItem(id: 'home', icon: LucideIcons.layoutDashboard, label: 'home'),
  NavItem(id: 'orders', icon: LucideIcons.layers, label: 'orders'),
  NavItem(id: 'invoices', icon: LucideIcons.receipt, label: 'invoices'),
  NavItem(id: 'tables', icon: LucideIcons.layoutGrid, label: 'tables'),
  NavItem(id: 'customers', icon: LucideIcons.users, label: 'customers'),
  NavItem(id: 'reports', icon: LucideIcons.fileText, label: 'reports'),
  NavItem(id: 'settings', icon: LucideIcons.settings, label: 'settings'),
];

// NOTE: All product, category, and table data is now fetched from the API
// Mock data has been removed. Data is loaded from:
// - ProductService.getProducts()
// - ProductService.getMealCategories()
// - BranchService.getEnabledPayMethods()
// - OrderService.getBookingSettings()
