import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../services/api/table_service.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../locator.dart';

class TableManagementScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Function(TableItem) onTableTap;

  const TableManagementScreen({
    super.key,
    required this.onBack,
    required this.onTableTap,
  });

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  final TableService _tableService = getIt<TableService>();

  bool _isLoading = true;
  String? _error;
  List<TableItem> _tables = [];

  final Map<String, bool> _deactivatedTables = {};
  final Map<String, Offset> _tablePositions = {};
  final GlobalKey _gridCanvasKey = GlobalKey();

  static const double _tableCardWidth = 250;
  static const double _tableCardHeight = 200;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
    _loadTables();
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTables() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tables = await _tableService.getTables();

      for (var table in tables) {
        _deactivatedTables[table.id] = !table.isActive;
      }

      if (mounted) {
        setState(() {
          _tables = tables;
          _initializeTablePositions();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _initializeTablePositions() {
    final filteredTables = _tables;
    final screenWidth = MediaQuery.of(context).size.width;

    const columns = 3;
    final spacingX = screenWidth / columns;
    const spacingY = 220.0;
    final startX = spacingX / 2 - 125;
    const startY = 50.0;

    for (int i = 0; i < filteredTables.length; i++) {
      final table = filteredTables[i];
      if (_tablePositions[table.id] == null) {
        final col = i % columns;
        final row = i ~/ columns;
        _tablePositions[table.id] = Offset(
          startX + col * spacingX,
          startY + row * spacingY,
        );
      }
    }
  }

  void _updateTablePosition(String tableId, Offset newPosition) {
    setState(() {
      _tablePositions[tableId] = newPosition;
    });
  }

  Future<void> _checkTableStatus(TableItem table) async {
    final tableDetails = await _tableService.getTableDetails(table.id);

    if (tableDetails == null || !tableDetails.isActive) {
      if (mounted) {
        _deactivatedTables[table.id] = true;
        setState(() {});

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.block, color: Colors.red),
                const SizedBox(width: 8),
                Text(translationService.t('table_unavailable')),
              ],
            ),
            content: Text(
              translationService.t('table_disabled_by_admin'),
              textAlign: TextAlign.right,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(translationService.t('ok')),
              ),
            ],
          ),
        );
      }
    } else {
      // If the detail response has no id (malformed API response), fall back to
      // the original table from the list which always has a valid id.
      final resolvedTable =
          tableDetails.id.trim().isNotEmpty ? tableDetails : table;
      final waiterLabel = resolvedTable.waiterName?.trim() ?? '';
      final isUnavailable = resolvedTable.status != TableStatus.available;

      if (isUnavailable) {
        if (!mounted) return;
        final isReservedState = resolvedTable.status == TableStatus.occupied &&
            waiterLabel.contains('محجوز');
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.event_busy, color: Colors.orange),
                const SizedBox(width: 8),
                Text(isReservedState
                    ? translationService.t('table_reserved')
                    : translationService.t('table_occupied')),
              ],
            ),
            content: Text(
              isReservedState
                  ? translationService.t('table_cannot_create_order_reserved')
                  : translationService.t('table_cannot_create_order_open'),
              textAlign: TextAlign.right,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(translationService.t('ok')),
              ),
            ],
          ),
        );
        return;
      }

      // Table is active and available, proceed.
      widget.onTableTap(resolvedTable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 1100;

    final filteredTables = _tables;

    return Scaffold(
      backgroundColor: context.appBg,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: context.appCardBg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isCompact
                  ? Row(
                      children: [
                        IconButton(
                          onPressed: widget.onBack,
                          icon: const Icon(LucideIcons.chevronRight),
                          color: const Color(0xFFF58220),
                        ),
                        Expanded(
                          child: Text(
                            translationService.t('tables_management'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        // Waiter-mode shortcut intentionally removed — the
                        // module stays on disk but no UI exposes it.
                        IconButton(
                          onPressed: _loadTables,
                          icon: const Icon(LucideIcons.refreshCw),
                          color: const Color(0xFFF58220),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: widget.onBack,
                          icon: const Icon(LucideIcons.chevronRight, size: 28),
                          label: Text(translationService.t('back'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFF58220),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                        Text(translationService.t('tables_management'),
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E293B))),
                        // Waiter-mode shortcut intentionally removed — the
                        // module stays on disk but no UI exposes it.
                        _HeaderActionBtn(
                          icon: LucideIcons.refreshCw,
                          label: translationService.t('refresh'),
                          onTap: _loadTables,
                        ),
                      ],
                    ),
            ),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : filteredTables.isEmpty
                          ? _buildEmptyView()
                          : _buildTableGrid(filteredTables),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.alertCircle, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            translationService.t('error'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadTables,
            icon: const Icon(LucideIcons.refreshCw),
            label: Text(translationService.t('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.layers, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(translationService.t('no_data'),
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTableGrid(List<TableItem> tables) {
    final screenSize = MediaQuery.of(context).size;
    final isCompact = screenSize.width < 900;

    if (isCompact) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: screenSize.width < 430 ? 220 : 260,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: screenSize.width < 430 ? 0.92 : 1.0,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) {
          final table = tables[index];
          final isDeactivated = _deactivatedTables[table.id] ?? false;

          // Waiter-specific callbacks are intentionally null: the module
          // still exists but its UI is hidden everywhere. Seats count falls
          // back to `table.seats` from the API.
          return _NormalTableCard(
            table: table,
            isDeactivated: isDeactivated,
            compact: true,
            width: double.infinity,
            height: double.infinity,
            onTap: isDeactivated ? null : () => _checkTableStatus(table),
          );
        },
      );
    }

    final defaultCanvasWidth = screenSize.width;
    final defaultCanvasHeight = math.max(420.0, screenSize.height - 260);

    const canvasPadding = 80.0;
    double canvasWidth = defaultCanvasWidth;
    double canvasHeight = defaultCanvasHeight;

    for (final table in tables) {
      final position = _tablePositions[table.id] ?? const Offset(100, 100);
      canvasWidth = math.max(
        canvasWidth,
        position.dx + _tableCardWidth + canvasPadding,
      );
      canvasHeight = math.max(
        canvasHeight,
        position.dy + _tableCardHeight + canvasPadding,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          key: _gridCanvasKey,
          width: canvasWidth,
          height: canvasHeight,
          child: Stack(
            children: [
              // PERF: stable ValueKey per table so Flutter can reuse the
              // underlying Element/RenderObject across rebuilds (e.g. after
              // drag or refresh) instead of tearing down and re-creating
              // every card.
              ...tables.map((rawTable) {
                final table = rawTable;
                final isDeactivated = _deactivatedTables[table.id] ?? false;
                final position =
                    _tablePositions[table.id] ?? const Offset(100, 100);

                return _DraggableTableCard(
                  key: ValueKey('table_${table.id}'),
                  table: table,
                  isDeactivated: isDeactivated,
                  initialPosition: position,
                  canvasKey: _gridCanvasKey,
                  canvasSize: Size(canvasWidth, canvasHeight),
                  onTap: isDeactivated ? null : () => _checkTableStatus(table),
                  onPositionChanged: (newPosition) =>
                      _updateTablePosition(table.id, newPosition),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    const gridSize = 50.0;

    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DraggableTableCard extends StatefulWidget {
  final TableItem table;
  final bool isDeactivated;
  final Offset initialPosition;
  final GlobalKey canvasKey;
  final Size canvasSize;
  final VoidCallback? onTap;
  final Function(Offset) onPositionChanged;

  const _DraggableTableCard({
    super.key,
    required this.table,
    required this.isDeactivated,
    required this.initialPosition,
    required this.canvasKey,
    required this.canvasSize,
    required this.onTap,
    required this.onPositionChanged,
  });

  @override
  State<_DraggableTableCard> createState() => _DraggableTableCardState();
}

class _DraggableTableCardState extends State<_DraggableTableCard> {
  static const double _cardWidth = 250;
  static const double _cardHeight = 200;

  late Offset _currentPosition;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _currentPosition.dx,
      top: _currentPosition.dy,
      child: Draggable<Offset>(
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: _cardWidth,
            height: _cardHeight,
            child: _NormalTableCard(
              table: widget.table,
              isDeactivated: widget.isDeactivated,
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: SizedBox(
            width: _cardWidth,
            height: _cardHeight,
            child: _NormalTableCard(
              table: widget.table,
              isDeactivated: widget.isDeactivated,
            ),
          ),
        ),
        onDragEnd: (details) {
          final renderBox = widget.canvasKey.currentContext?.findRenderObject();
          if (renderBox is! RenderBox) return;

          final localPosition = renderBox.globalToLocal(details.offset);
          final maxX = math.max(0.0, widget.canvasSize.width - _cardWidth);
          final maxY = math.max(0.0, widget.canvasSize.height - _cardHeight);
          final clamped = Offset(
            localPosition.dx.clamp(0.0, maxX).toDouble(),
            localPosition.dy.clamp(0.0, maxY).toDouble(),
          );

          setState(() => _currentPosition = clamped);
          widget.onPositionChanged(clamped);
        },
        child: SizedBox(
          width: _cardWidth,
          height: _cardHeight,
          child: Stack(
            children: [
              _NormalTableCard(
                table: widget.table,
                isDeactivated: widget.isDeactivated,
                onTap: widget.onTap,
              ),
              // Drag handle indicator
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF58220),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.move,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NormalTableCard extends StatelessWidget {
  final TableItem table;
  final bool isDeactivated;
  final VoidCallback? onTap;
  final bool compact;
  final double? width;
  final double? height;

  const _NormalTableCard({
    required this.table,
    required this.isDeactivated,
    this.onTap,
    this.compact = false,
    this.width,
    this.height,
  });

  Color _getStatusColor(TableStatus status) {
    if (isDeactivated) return Colors.grey;
    switch (status) {
      case TableStatus.available:
        return const Color(0xFF10B981);
      case TableStatus.occupied:
        return const Color(0xFFEF4444);
      case TableStatus.printed:
        return const Color(0xFFF59E0B);
    }
  }

  Color _getStatusBg(TableStatus status) {
    if (isDeactivated) return Colors.grey.shade100;
    switch (status) {
      case TableStatus.available:
        return const Color(0xFFECFDF5);
      case TableStatus.occupied:
        return const Color(0xFFFEF2F2);
      case TableStatus.printed:
        return const Color(0xFFFFFBEB);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(table.status);
    final statusBg = _getStatusBg(table.status);
    final waiterLabel = table.waiterName?.trim() ?? '';
    final isReservedState =
        table.status == TableStatus.occupied && waiterLabel.contains('محجوز');

    return SizedBox(
      width: width ?? 250,
      height: height ?? 200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ultraCompact =
              constraints.maxWidth < 170 || constraints.maxHeight < 130;
          final effectiveCompact = compact ||
              ultraCompact ||
              constraints.maxWidth < 220 ||
              constraints.maxHeight < 170;

          final borderRadius = effectiveCompact ? 16.0 : 20.0;
          final outerPadding =
              ultraCompact ? 8.0 : (effectiveCompact ? 12.0 : 20.0);
          final headerHeight = effectiveCompact ? 5.0 : 6.0;
          final usersIconSize =
              ultraCompact ? 14.0 : (effectiveCompact ? 16.0 : 18.0);
          final seatsFontSize =
              ultraCompact ? 11.0 : (effectiveCompact ? 12.0 : 14.0);
          final tableNumberFontSize =
              ultraCompact ? 24.0 : (effectiveCompact ? 30.0 : 36.0);
          final statusFontSize =
              ultraCompact ? 10.0 : (effectiveCompact ? 11.0 : 12.0);
          final waiterFontSize =
              ultraCompact ? 10.0 : (effectiveCompact ? 11.0 : 12.0);
          final stateFontSize =
              ultraCompact ? 11.0 : (effectiveCompact ? 13.0 : 14.0);

          return RepaintBoundary(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isDeactivated ? null : onTap,
                borderRadius: BorderRadius.circular(borderRadius),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: context.appCardBg,
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(
                      color: isDeactivated
                          ? Colors.grey.shade300
                          : table.status == TableStatus.available
                              ? Colors.grey.withValues(alpha: 0.1)
                              : statusColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Container(
                        height: headerHeight,
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(borderRadius),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(outerPadding),
                        child: Column(
                          mainAxisAlignment: ultraCompact
                              ? MainAxisAlignment.spaceEvenly
                              : MainAxisAlignment.center,
                          children: [
                            if (!ultraCompact)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.users,
                                    size: usersIconSize,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(width: 6),
                                  // Seats come straight from the API so
                                  // cards always show the table's capacity,
                                  // independent of the (now-hidden) waiter
                                  // registry.
                                  Text(
                                    translationService.t('persons_count',
                                        args: {'count': table.seats}),
                                    style: TextStyle(
                                      fontSize: seatsFontSize,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                  if (table.qrImage != null) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      LucideIcons.qrCode,
                                      size: effectiveCompact ? 14 : 16,
                                      color: const Color(0xFFF58220),
                                    ),
                                  ],
                                ],
                              ),
                            if (!ultraCompact)
                              SizedBox(height: effectiveCompact ? 8 : 12),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  table.number,
                                  style: TextStyle(
                                    fontSize: tableNumberFontSize,
                                    fontWeight: FontWeight.w900,
                                    // Match the reference palette: dark ink
                                    // when available, status tint otherwise,
                                    // grey when disabled.
                                    color: isDeactivated
                                        ? Colors.grey
                                        : table.status == TableStatus.available
                                            ? const Color(0xFF1E293B)
                                            : statusColor,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                                height: ultraCompact
                                    ? 4
                                    : (effectiveCompact ? 8 : 12)),
                            if (!isDeactivated &&
                                table.status != TableStatus.available) ...[
                              if (ultraCompact)
                                Text(
                                  table.status == TableStatus.printed
                                      ? translationService.t('printed')
                                      : translationService.t('occupied'),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: stateFontSize,
                                  ),
                                )
                              else ...[
                                if (!isReservedState)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.clock,
                                          size: effectiveCompact ? 11 : 12,
                                          color: statusColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${table.occupiedMinutes} ${translationService.t('minutes_label')}',
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: statusFontSize,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (table.status == TableStatus.occupied)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: isReservedState ? 0 : 8,
                                    ),
                                    child: Text(
                                      table.waiterName ?? 'Branch Manager',
                                      style: TextStyle(
                                        color:
                                            statusColor.withValues(alpha: 0.8),
                                        fontSize: waiterFontSize,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ] else if (!isDeactivated)
                              Text(
                                translationService.t('available'),
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.bold,
                                  fontSize: stateFontSize,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (table.isPaid && !isDeactivated)
                        Positioned(
                          top: effectiveCompact ? 10 : 16,
                          left: effectiveCompact ? 10 : 16,
                          child: Container(
                            padding: EdgeInsets.all(effectiveCompact ? 5 : 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFDCFCE7),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.check,
                              color: const Color(0xFF15803D),
                              size: effectiveCompact ? 14 : 16,
                            ),
                          ),
                        ),
                      if (isDeactivated)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(borderRadius),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.ban,
                                    color: Colors.white,
                                    size: ultraCompact
                                        ? 22
                                        : (effectiveCompact ? 26 : 32),
                                  ),
                                  SizedBox(height: ultraCompact ? 4 : 8),
                                  Text(
                                    translationService.t('disabled'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: ultraCompact
                                          ? 12
                                          : (effectiveCompact ? 14 : 16),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (!ultraCompact) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      translationService
                                          .t('disabled_by_management'),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: effectiveCompact ? 11 : 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const btnColor = Color(0xFFF58220);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 8,
        ),
        child: Row(
          children: [
            Icon(icon, color: btnColor, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: btnColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

