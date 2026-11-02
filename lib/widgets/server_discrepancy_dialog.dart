import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../services/discrepancy_audit_service.dart';
import '../services/supabase_sync_service.dart';

class ServerDiscrepancyDialog extends StatefulWidget {
  final String initialCategoryKey;

  const ServerDiscrepancyDialog({
    super.key,
    this.initialCategoryKey = 'sales_invoices',
  });

  static Future<void> show(BuildContext context, {String initialCategoryKey = 'sales_invoices'}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ServerDiscrepancyDialog(initialCategoryKey: initialCategoryKey),
    );
  }

  @override
  State<ServerDiscrepancyDialog> createState() => _ServerDiscrepancyDialogState();
}

class _ServerDiscrepancyDialogState extends State<ServerDiscrepancyDialog> {
  late String _selectedCategory;
  bool _showOnlyDiscrepancies = false;
  bool _isLoading = false;
  List<DiscrepancyRecord> _records = [];

  // Draggable & Resizable State
  Offset _dialogPosition = const Offset(0, 0);
  Size _dialogSize = const Size(1150, 720);

  final _categories = [
    {'key': 'sales_invoices', 'label': 'Sales Invoices & Counter Bills', 'icon': Icons.point_of_sale_rounded},
    {'key': 'purchase_entries', 'label': 'Purchase Inward Entries', 'icon': Icons.shopping_bag_rounded},
    {'key': 'stock_batches', 'label': 'Active Stock Batches (Inventory)', 'icon': Icons.layers_rounded},
    {'key': 'sales_return_invoices', 'label': 'Sales Return Receipts', 'icon': Icons.assignment_return_rounded},
    {'key': 'purchase_return_entries', 'label': 'Purchase Return Entries', 'icon': Icons.unarchive_rounded},
    {'key': 'product_master', 'label': 'Registered Products (Product Master)', 'icon': Icons.inventory_2_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategoryKey;
    _loadDiscrepancies();
  }

  String _formatDateStr(String dateStr) {
    if (dateStr.isEmpty || dateStr == '-') return '-';
    if (dateStr.contains('T')) {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) {
        return DateFormat('dd/MM/yyyy hh:mm a').format(dt);
      }
    }
    return dateStr;
  }

  String _formatValue(dynamic val) {
    if (val == null) return '-';
    final str = val.toString().trim();
    if (str.isEmpty) return '-';

    final n = num.tryParse(str);
    if (n != null) {
      if (n == 0) return '0.00';
      return NumberFormat('#,##,##0.00').format(n);
    }

    if (str.contains('T') && str.length >= 10) {
      final dt = DateTime.tryParse(str);
      if (dt != null) {
        return DateFormat('dd/MM/yyyy hh:mm a').format(dt);
      }
    }

    return str;
  }

  Future<void> _reconcileCategoryBiDirectionally() async {
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('⚡ Running Smart 2-Way Reconciliation on all discrepancies...'), duration: Duration(seconds: 2)),
    );
    try {
      final count = await DiscrepancyAuditService.instance.reconcileCategoryBiDirectionally(_selectedCategory);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('✅ Smart 2-Way Merge completed ($count records reconciled)!'), backgroundColor: Colors.green.shade800),
      );
    } catch (e) {
      debugPrint('Reconcile category error: $e');
    } finally {
      await _loadDiscrepancies();
    }
  }

  Future<void> _reconcileSingleRecord(DiscrepancyRecord record) async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('⚡ Reconciling entry #${record.primaryKey}...'), duration: const Duration(seconds: 1)),
    );
    try {
      final ok = await DiscrepancyAuditService.instance.reconcileRecordBiDirectionally(record);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Entry #${record.primaryKey} reconciled and merged successfully!'), backgroundColor: Colors.green.shade800),
        );
      }
    } catch (e) {
      debugPrint('Reconcile record error: $e');
    } finally {
      await _loadDiscrepancies();
    }
  }

  Future<void> _loadDiscrepancies() async {
    setState(() => _isLoading = true);
    try {
      final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
      await SupabaseSyncService.instance.syncAllPendingCloudRecords(pharmacy: pharmacy);
    } catch (_) {}
    final results = await DiscrepancyAuditService.instance.fetchDiscrepancies(
      categoryKey: _selectedCategory,
      showOnlyDiscrepancies: _showOnlyDiscrepancies,
    );
    if (!mounted) return;
    setState(() {
      _records = results;
      _isLoading = false;
    });
  }

  // --- Visual Sales / Purchase Entry Form Replica Inspector Modal ---
  void _showRecordDetailModal(int initialIndex) {
    int currentIndex = initialIndex;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final record = _records[currentIndex];
          final fmt = NumberFormat('#,##,##0.00');

          void goToPrevious() {
            if (currentIndex > 0) {
              setModalState(() => currentIndex--);
            }
          }

          void goToNext() {
            if (currentIndex < _records.length - 1) {
              setModalState(() => currentIndex++);
            }
          }

          // Extract Field Mismatches
          DiscrepancyField? mobField;
          DiscrepancyField? custField;
          DiscrepancyField? agentField;
          DiscrepancyField? subtotalField;
          DiscrepancyField? discountField;
          DiscrepancyField? roundOffField;
          DiscrepancyField? grandTotalField;

          for (var f in record.fields) {
            if (f.fieldName == 'mobile' || f.fieldName == 'phone') mobField = f;
            if (f.fieldName == 'customer') custField = f;
            if (f.fieldName == 'agent') agentField = f;
            if (f.fieldName == 'subtotal') subtotalField = f;
            if (f.fieldName == 'discount_amount') discountField = f;
            if (f.fieldName == 'round_off') roundOffField = f;
            if (f.fieldName == 'net_amount' || f.fieldName == 'grand_total') grandTotalField = f;
          }

          final String mobVal = (record.localData['mobile'] ?? record.localData['phone'] ?? record.serverData['mobile'] ?? record.serverData['phone'] ?? mobField?.localValue ?? '-').toString();
          final bool isMobMismatch = (mobField?.isMismatch ?? false);
          final bool isCustMismatch = (custField?.isMismatch ?? false) || record.isMissingOnServer || record.isMissingLocally;
          final bool isSubtotalMismatch = subtotalField?.isMismatch ?? false;
          final bool isGrandTotalMismatch = (grandTotalField?.isMismatch ?? false) || record.isMissingOnServer || record.isMissingLocally;

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  goToPrevious();
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  goToNext();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                width: 1050,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Bar with Title & Entry Counter
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded, color: Colors.blue, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Entry Replica Inspector: ${record.title}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Text(
                            'Entry ${currentIndex + 1} of ${_records.length}',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Top Warning Banner if Missing on Server or Local
                    if (record.isMissingOnServer)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '🔴 RECORD NOT UPLOADED TO CLOUD SERVER (Exists on Local PC, Missing on Supabase Server)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red.shade900),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (record.isMissingLocally)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '🔴 RECORD MISSING ON LOCAL DATABASE (Exists on Supabase Server, Missing in Local PC)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Top Entry Form Header Fields (Replica of Sales Entry Screen)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _formBox('Entry No:', record.primaryKey)),
                          const SizedBox(width: 8),
                          Expanded(child: _formBox('Acc / Mode:', record.paymentMode)),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: _formBox(
                              'Patient / Customer:',
                              record.customer,
                              isRed: isCustMismatch,
                              subNote: isCustMismatch && custField != null ? 'Server: ${custField.serverValue ?? 'NOT ON SERVER'}' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: _formBox(
                              'Mob / Phone:',
                              mobVal.isEmpty ? '-' : mobVal,
                              isRed: isMobMismatch,
                              subNote: isMobMismatch && mobField != null ? 'Server: ${mobField.serverValue ?? '-'}' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: _formBox('Date & Time:', _formatDateStr(record.date)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: _formBox('Doctor:', record.doctor)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _formBox('Agent / Staff:', record.agent, isRed: agentField?.isMismatch ?? false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Middle Line Items Data Grid (Replica of Entry Form Table)
                    const Text('Line Items (Products & Batches):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: record.itemRows.isEmpty
                            ? const Center(
                                child: Text('No item details available for this record.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              )
                            : SingleChildScrollView(
                                child: Table(
                                  border: TableBorder.all(color: Colors.grey.shade200),
                                  columnWidths: const {
                                    0: FlexColumnWidth(0.5),  // #
                                    1: FlexColumnWidth(2.5),  // PRODUCT NAME
                                    2: FlexColumnWidth(1.1),  // BATCH
                                    3: FlexColumnWidth(1.0),  // EXPIRY
                                    4: FlexColumnWidth(1.1),  // QTY
                                    5: FlexColumnWidth(1.0),  // F.QTY
                                    6: FlexColumnWidth(1.1),  // MRP
                                    7: FlexColumnWidth(1.1),  // RATE
                                    8: FlexColumnWidth(1.1),  // DISC %
                                    9: FlexColumnWidth(1.5),  // TOTAL AMOUNT
                                  },
                                  children: [
                                    TableRow(
                                      decoration: BoxDecoration(color: Colors.grey.shade200),
                                      children: const [
                                        Padding(padding: EdgeInsets.all(6), child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('PRODUCT NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('BATCH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('EXPIRY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('QTY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('F.QTY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('MRP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('RATE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('DISC %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('TOTAL AMOUNT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                      ],
                                    ),
                                    ...record.itemRows.asMap().entries.map((entry) {
                                      final iIdx = entry.key;
                                      final item = entry.value;
                                      final bool isItemRed = item.isMismatch || record.isMissingOnServer || record.isMissingLocally;

                                      final bool isQtyDiff = (item.qtyLoc - item.qtySrv).abs() > 0.01;
                                      final bool isFQtyDiff = (item.fQtyLoc - item.fQtySrv).abs() > 0.01;
                                      final bool isDiscDiff = (item.discPercentLoc - item.discPercentSrv).abs() > 0.01;
                                      final bool isTotalDiff = (item.totalLoc - item.totalSrv).abs() > 0.01;

                                      return TableRow(
                                        decoration: BoxDecoration(
                                          color: isItemRed ? Colors.red.shade50 : Colors.white,
                                        ),
                                        children: [
                                          Padding(padding: const EdgeInsets.all(6), child: Text('${iIdx + 1}', style: const TextStyle(fontSize: 11))),
                                          Padding(padding: const EdgeInsets.all(6), child: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                          Padding(padding: const EdgeInsets.all(6), child: Text(item.batchNumber, style: const TextStyle(fontSize: 11))),
                                          Padding(padding: const EdgeInsets.all(6), child: Text(item.expiryDate, style: const TextStyle(fontSize: 11))),
                                          Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Text(
                                              isQtyDiff ? '${item.qtyLoc} (Srv: ${item.qtySrv})' : '${item.qtyLoc}',
                                              style: TextStyle(fontWeight: FontWeight.bold, color: isQtyDiff ? Colors.red.shade900 : Colors.black87, fontSize: 11),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Text(
                                              isFQtyDiff ? '${item.fQtyLoc} (Srv: ${item.fQtySrv})' : '${item.fQtyLoc}',
                                              style: TextStyle(fontSize: 11, color: isFQtyDiff ? Colors.red.shade900 : Colors.black87),
                                            ),
                                          ),
                                          Padding(padding: const EdgeInsets.all(6), child: Text('₹${fmt.format(item.mrpLoc)}', style: const TextStyle(fontSize: 11))),
                                          Padding(padding: const EdgeInsets.all(6), child: Text('₹${fmt.format(item.rateLoc)}', style: const TextStyle(fontSize: 11))),
                                          Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Text(
                                              isDiscDiff ? '${item.discPercentLoc}% (Srv: ${item.discPercentSrv}%)' : '${item.discPercentLoc}%',
                                              style: TextStyle(fontSize: 11, color: isDiscDiff ? Colors.red.shade900 : Colors.black87),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Text(
                                              isTotalDiff
                                                  ? '₹${fmt.format(item.totalLoc)} (Srv: ₹${fmt.format(item.totalSrv)})'
                                                  : '₹${fmt.format(item.totalLoc)}',
                                              style: TextStyle(fontWeight: FontWeight.bold, color: isTotalDiff ? Colors.red.shade900 : Colors.black87, fontSize: 11),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Bottom Summary & Financial Totals Bar (Replica of Entry Form Totals)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _totalSummaryTile(
                            'Sub Total',
                            subtotalField?.localValue ?? grandTotalField?.localValue ?? 0,
                            subtotalField?.serverValue ?? grandTotalField?.serverValue ?? 0,
                            isRed: isSubtotalMismatch,
                          ),
                          _totalSummaryTile(
                            'Discount',
                            discountField?.localValue ?? 0,
                            discountField?.serverValue ?? 0,
                          ),
                          _totalSummaryTile(
                            'Round Off',
                            roundOffField?.localValue ?? 0,
                            roundOffField?.serverValue ?? 0,
                          ),
                          _totalSummaryTile(
                            'Grand Total',
                            grandTotalField?.localValue ?? 0,
                            grandTotalField?.serverValue ?? 0,
                            isRed: isGrandTotalMismatch,
                            isBoldLarge: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Bottom Navigation Buttons Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: currentIndex > 0 ? goToPrevious : null,
                              icon: const Icon(Icons.arrow_back_rounded, size: 16),
                              label: const Text('Previous (<)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueGrey,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: currentIndex < _records.length - 1 ? goToNext : null,
                              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                              label: const Text('Next (>)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                _reconcileSingleRecord(record);
                              },
                              icon: const Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
                              label: const Text('⚡ RECONCILE & MERGE THIS ENTRY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade900,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _formBox(String label, String value, {bool isRed = false, String? subNote}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isRed ? Colors.red.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isRed ? Colors.red.shade400 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: isRed ? Colors.red.shade900 : Colors.blueGrey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isRed ? Colors.red.shade900 : Colors.black87),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subNote != null)
            Text(
              subNote,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red.shade800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _totalSummaryTile(String label, dynamic locVal, dynamic srvVal, {bool isRed = false, bool isBoldLarge = false}) {
    final fmt = NumberFormat('#,##,##0.00');
    final locNum = num.tryParse(locVal.toString()) ?? 0;
    final srvNum = num.tryParse(srvVal.toString()) ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isRed ? Colors.red.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isRed ? Colors.red.shade400 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: isRed ? Colors.red.shade900 : Colors.blueGrey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            '₹${fmt.format(locNum)}',
            style: TextStyle(
              fontSize: isBoldLarge ? 14 : 12,
              fontWeight: FontWeight.bold,
              color: isRed ? Colors.red.shade900 : Colors.black87,
            ),
          ),
          if (isRed)
            Text(
              '(Server: ₹${fmt.format(srvNum)})',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCat = _categories.firstWhere((c) => c['key'] == _selectedCategory, orElse: () => _categories.first);
    final fmt = NumberFormat('#,##,###.##');
    final int mismatchCount = _records.where((r) => r.hasDiscrepancy).length;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Transform.translate(
        offset: _dialogPosition,
        child: Container(
          width: _dialogSize.width,
          height: _dialogSize.height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 4),
            ],
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Stack(
            children: [
              // Dialog Main Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Draggable Header Bar
                    GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _dialogPosition += details.delta;
                        });
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.drag_indicator_rounded, color: Colors.grey, size: 22),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: const Icon(Icons.youtube_searched_for_rounded, color: Colors.red, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cloud Server vs. Local PC Discrepancy & Hole Audit (Movable & Resizable)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    'Read-only inspection report • Drag header to move • Drag bottom-right corner to resize',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Controls Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Text('Category:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              value: _selectedCategory,
                              underline: const SizedBox(),
                              icon: const Icon(Icons.arrow_drop_down_rounded),
                              items: _categories.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c['key'] as String,
                                  child: Row(
                                    children: [
                                      Icon(c['icon'] as IconData, size: 18, color: Colors.blue.shade800),
                                      const SizedBox(width: 8),
                                      Text(c['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null && val != _selectedCategory) {
                                  setState(() => _selectedCategory = val);
                                  _loadDiscrepancies();
                                }
                              },
                            ),
                            const SizedBox(width: 24),
                            FilterChip(
                              selected: _showOnlyDiscrepancies,
                              showCheckmark: true,
                              avatar: const Icon(Icons.filter_alt_rounded, size: 16),
                              label: Text('🔥 Show Red Only ($mismatchCount)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              selectedColor: Colors.red.shade100,
                              checkmarkColor: Colors.red.shade800,
                              onSelected: (val) {
                                setState(() => _showOnlyDiscrepancies = val);
                                _loadDiscrepancies();
                              },
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade900,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.bolt_rounded, size: 16),
                              label: const Text('⚡ SMART 2-WAY MERGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              onPressed: _isLoading ? null : () => _reconcileCategoryBiDirectionally(),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                              label: const Text('RESET CLOUD & RE-EXPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              onPressed: _isLoading ? null : () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogCtx) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    title: const Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                                        SizedBox(width: 10),
                                        Text('Purge Remote Cloud & Re-Export?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      ],
                                    ),
                                    content: Text(
                                      'This will purge duplicate/stale records in Supabase Cloud for "$_selectedCategory" and re-export your local PC catalog to Supabase Cloud Server.',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialogCtx, false),
                                        child: const Text('CANCEL'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(dialogCtx, true),
                                        child: const Text('YES, PURGE & RE-EXPORT', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  if (!context.mounted) return;
                                  final messenger = ScaffoldMessenger.of(context);
                                  setState(() => _isLoading = true);
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('⚡ Purging remote cloud entries and re-uploading local catalog...'), duration: Duration(seconds: 3)),
                                  );
                                  try {
                                    await SupabaseSyncService.instance.purgeAndReSyncCategory(_selectedCategory);
                                  } catch (e) {
                                    debugPrint('Error during purge and re-sync: $e');
                                  } finally {
                                    if (mounted) {
                                      await _loadDiscrepancies();
                                    }
                                  }
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.cloud_download_rounded, size: 16),
                              label: const Text('PULL & FIX DISCREPANCIES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              onPressed: _isLoading ? null : () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('⚡ Pulling missing records from cloud server...'), duration: Duration(seconds: 2)),
                                );
                                Set<String>? categoryFilter;
                                if (_selectedCategory == 'sales_invoices') categoryFilter = {'sales'};
                                if (_selectedCategory == 'purchase_entries') categoryFilter = {'purchases'};
                                if (_selectedCategory == 'stock_batches') categoryFilter = {'batches'};
                                if (_selectedCategory == 'sales_return_invoices') categoryFilter = {'sales_returns'};
                                if (_selectedCategory == 'purchase_return_entries') categoryFilter = {'purchase_returns'};
                                if (_selectedCategory == 'product_master') categoryFilter = {'products'};

                                final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
                                await SupabaseSyncService.instance.syncPendingCloudSalesAndPurchases(pharmacy: pharmacy);
                                await SupabaseSyncService.instance.syncAllPendingData(
                                  forceFull: true,
                                  isExportMode: false,
                                  isManualTransfer: true,
                                  selectedCategories: categoryFilter,
                                );
                                await _loadDiscrepancies();
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Refresh Audit Data',
                              icon: const Icon(Icons.refresh_rounded, color: Colors.blue),
                              onPressed: _loadDiscrepancies,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Summary Counts
                    Row(
                      children: [
                        Text(
                          'Total Entries: ${_records.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: mismatchCount == 0 ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: mismatchCount == 0 ? Colors.green.shade300 : Colors.red.shade300),
                          ),
                          child: Text(
                            mismatchCount == 0
                                ? '✅ All Entries Match Perfectly'
                                : '⚠️ $mismatchCount Non-Matching / Missing Entry Holes Detected',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: mismatchCount == 0 ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Main Table View
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('Comparing Local SQLite vs Supabase Cloud...', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            )
                          : _records.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline_rounded, size: 56, color: Colors.green.shade400),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No Records Found!',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'No entries available for ${activeCat['label']}.',
                                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SingleChildScrollView(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                                          dataRowMaxHeight: 52,
                                          columns: const [
                                            DataColumn(label: Text('INV / ENTRY NO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                            DataColumn(label: Text('DATE & TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                            DataColumn(label: Text('CUSTOMER / PARTY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                            DataColumn(label: Text('AGENT / STAFF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                            DataColumn(label: Text('TOTAL AMOUNT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                            DataColumn(label: Text('LOCAL STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                            DataColumn(label: Text('SERVER STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                            DataColumn(label: Text('ACTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          ],
                                          rows: _records.asMap().entries.map((entry) {
                                            final idx = entry.key;
                                            final rec = entry.value;

                                            DiscrepancyField? totalField;
                                            try {
                                              totalField = rec.fields.firstWhere(
                                                (f) =>
                                                    f.fieldName == 'net_amount' ||
                                                    f.fieldName == 'grand_total' ||
                                                    f.fieldName == 'total_amount' ||
                                                    f.fieldName == 'quantity',
                                              );
                                            } catch (_) {}

                                            final bool isTotalMismatch = totalField?.isMismatch ?? false;
                                            final srvAmt = totalField?.serverValue;
                                            final locAmt = totalField?.localValue;

                                            return DataRow(
                                              color: WidgetStateProperty.all(
                                                rec.hasDiscrepancy ? Colors.red.shade50.withValues(alpha: 0.3) : Colors.white,
                                              ),
                                              cells: [
                                                DataCell(
                                                  Text(
                                                    rec.primaryKey,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _formatDateStr(rec.date),
                                                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    rec.customer,
                                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    rec.agent,
                                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                                  ),
                                                ),
                                                DataCell(
                                                  isTotalMismatch
                                                      ? Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: Colors.red.shade100,
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: Colors.red.shade400),
                                                          ),
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Text(
                                                                srvAmt is num ? '₹${fmt.format(srvAmt)}' : '${srvAmt ?? '0'}',
                                                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900, fontSize: 11),
                                                              ),
                                                              Text(
                                                                locAmt is num ? '(Local ₹${fmt.format(locAmt)})' : '(Local ${locAmt ?? '0'})',
                                                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800, fontSize: 10),
                                                              ),
                                                            ],
                                                          ),
                                                        )
                                                      : Text(
                                                          srvAmt is num
                                                              ? '₹${fmt.format(srvAmt)}'
                                                              : locAmt is num
                                                                  ? '₹${fmt.format(locAmt)}'
                                                                  : '${srvAmt ?? locAmt ?? '₹0.00'}',
                                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                                                        ),
                                                ),
                                                DataCell(
                                                  rec.isMissingLocally
                                                      ? Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: Colors.red.shade100,
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: Colors.red.shade400),
                                                          ),
                                                          child: const Text('NOT ON LOCAL [RED]', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                                                        )
                                                      : const Text('Local: Synced', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                                                ),
                                                DataCell(
                                                  rec.isMissingOnServer
                                                      ? Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: Colors.red.shade100,
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: Colors.red.shade400),
                                                          ),
                                                          child: const Text('NOT ON SERVER [RED]', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                                                        )
                                                      : const Text('Server: Synced', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                                                ),
                                                DataCell(
                                                  IconButton(
                                                    tooltip: 'Inspect Entry Form Replica',
                                                    icon: const Icon(Icons.visibility_rounded, color: Colors.blue, size: 20),
                                                    onPressed: () => _showRecordDetailModal(idx),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
              ),

              // Bottom Right Resizable Drag Handle
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _dialogSize = Size(
                        (_dialogSize.width + details.delta.dx).clamp(750.0, 1600.0),
                        (_dialogSize.height + details.delta.dy).clamp(480.0, 1000.0),
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    color: Colors.transparent,
                    child: const Icon(
                      Icons.aspect_ratio_rounded,
                      size: 18,
                      color: Colors.grey,
                    ),
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
