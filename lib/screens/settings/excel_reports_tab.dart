import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/theme_constants.dart';

class ExcelReportsTab extends StatefulWidget {
  final List<String> availableFinancialYears;
  final Future<void> Function({
    required String title,
    required Future<dynamic> Function(PharmacyProvider p, String path, Function(double, String) progress, String? fy) action,
    required bool isExport,
    required PharmacyProvider provider,
    String? financialYear,
  }) handleSync;
  final Future<void> Function({
    required String title,
    required Future<dynamic> Function(PharmacyProvider p, String? fy) deleteAction,
    required PharmacyProvider provider,
    String? financialYear,
  }) handleDelete;
  final Function(String, {bool isError}) showSnackBar;
  final Function(String, String) showErrorDialog;
  final Function(String, Stream<double>) showProgressDialog;

  const ExcelReportsTab({
    super.key,
    required this.availableFinancialYears,
    required this.handleSync,
    required this.handleDelete,
    required this.showSnackBar,
    required this.showErrorDialog,
    required this.showProgressDialog,
  });

  @override
  State<ExcelReportsTab> createState() => _ExcelReportsTabState();
}

class _ExcelReportsTabState extends State<ExcelReportsTab> {
  String? _salesFy = "All Years";
  String? _purchaseFy = "All Years";
  String? _salesReturnFy = "All Years";
  String? _purchaseReturnFy = "All Years";
  String? _damageFy = "All Years";

  Widget _buildSectionHeader(String title, String subtitle) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppStyles.h2Of(context)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: c.secondaryText, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Excel Reports & Bulk Utility Tools",
          "Export data to Excel for CA/GST tax filing, or import spreadsheets for bulk price editing.",
        ),
        const SizedBox(height: 24),
        // SET 1: Master Catalog & Current Inventory
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _dbActionTile(
              "Product Master",
              "Master catalog and product items",
              Icons.medication_rounded,
              Colors.purple.shade700,
              btnLabel: "EXPORT",
              headings: ["Name", "Packing", "RACK", "hsncode", "MRP", "P.RATE", "Patent", "Generic Name", "Gst", "Category", "Sub Category", "Sdisc%", "Schedule"],
              selectedFy: null,
              availableFys: null,
              onFyChanged: null,
              onTap: () => widget.handleSync(
                title: "Export Product Master",
                action: (p, path, progress, fy) => p.exportProductMasterToExcel(path, onProgress: progress),
                isExport: true,
                provider: provider,
                financialYear: null,
              ),
              importTap: () => widget.handleSync(
                title: "Import Product Master",
                action: (p, path, progress, fy) => p.importProductMasterFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: null,
              ),
              deleteTap: () => widget.handleDelete(
                title: "Product Master",
                deleteAction: (p, fy) => p.deleteProductMasterRecords(),
                provider: provider,
                financialYear: null,
              ),
            ),
            _dbActionTile(
              "Inventory",
              "Current stock and batch records",
              Icons.inventory_2_rounded,
              Colors.teal.shade700,
              btnLabel: "EXPORT",
              headings: ["Name", "Packing", "Stock", "Batch", "Expiry", "MRP", "L Cost", "MRP Value", "Supplier", "Gst%", "Category", "Sub Category"],
              selectedFy: null,
              availableFys: null,
              onFyChanged: null,
              onTap: () => widget.handleSync(
                title: "Export Inventory",
                action: (p, path, progress, fy) => p.exportInventoryToExcel(path, onProgress: progress),
                isExport: true,
                provider: provider,
                financialYear: null,
              ),
              importTap: () => widget.handleSync(
                title: "Import Inventory",
                action: (p, path, progress, fy) => p.importInventoryFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: null,
              ),
              deleteTap: () => widget.handleDelete(
                title: "Inventory",
                deleteAction: (p, fy) => p.deleteInventoryRecords(null),
                provider: provider,
                financialYear: null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // SET 2: Financial Year Transaction Logs & History
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _dbActionTile(
              "Sales History",
              "Billing and itemized records",
              Icons.point_of_sale_rounded,
              Colors.blue.shade700,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Time", "Patient", "Mobile", "Account", "Agent", "Product", "Packing", "Batch", "Qty", "S.Rate", "MRP", "Disc%", "Tax%", "Total", "Profit"],
              selectedFy: _salesFy,
              availableFys: widget.availableFinancialYears,
              onFyChanged: (fy) => setState(() => _salesFy = fy),
              onTap: () => widget.handleSync(
                title: "Export Sales",
                action: (p, path, progress, fy) => p.exportSalesToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _salesFy,
              ),
              importTap: () => widget.handleSync(
                title: "Import Sales",
                action: (p, path, progress, fy) => p.importSalesFromExcel(path, onProgress: progress, financialYear: fy),
                isExport: false,
                provider: provider,
                financialYear: _salesFy,
              ),
              deleteTap: () => widget.handleDelete(
                title: "Sales History",
                deleteAction: (p, fy) => p.deleteSalesRecords(fy),
                provider: provider,
                financialYear: _salesFy,
              ),
            ),
            _dbActionTile(
              "Purchase Logs",
              "Stock acquisition history",
              Icons.local_shipping_rounded,
              Colors.indigo,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Time", "Supplier", "Invoice No", "Inv Date", "Done By", "Product", "Batch", "Qty", "Packing", "P.Rate", "MRP", "Disc%", "Tax%", "Taxable Amount", "Grand Total"],
              selectedFy: _purchaseFy,
              availableFys: widget.availableFinancialYears,
              onFyChanged: (fy) => setState(() => _purchaseFy = fy),
              onTap: () => widget.handleSync(
                title: "Export Purchase",
                action: (p, path, progress, fy) => p.exportPurchaseToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _purchaseFy,
              ),
              importTap: () => widget.handleSync(
                title: "Import Purchase",
                action: (p, path, progress, fy) => p.importPurchaseFromExcel(path, onProgress: progress),
                isExport: false,
                provider: provider,
                financialYear: _purchaseFy,
              ),
              deleteTap: () => widget.handleDelete(
                title: "Purchase Logs",
                deleteAction: (p, fy) => p.deletePurchaseRecords(fy),
                provider: provider,
                financialYear: _purchaseFy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _dbActionTile(
              "Sales Returns",
              "Sales return logs",
              Icons.assignment_return_rounded,
              Colors.orange.shade700,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Customer", "Product", "Batch", "Pack", "Qty", "Total Amount", "Discount", "dis%", "gst%", "gst amt", "Ref Invoice", "Grand Total"],
              selectedFy: _salesReturnFy,
              availableFys: widget.availableFinancialYears,
              onFyChanged: (fy) => setState(() => _salesReturnFy = fy),
              onTap: () => widget.handleSync(
                title: "Export Sales Returns",
                action: (p, path, progress, fy) => p.exportSalesReturnsToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _salesReturnFy,
              ),
              importTap: () => widget.handleSync(
                title: "Import Sales Returns",
                action: (p, path, progress, fy) => p.importSalesReturnsFromExcel(path, onProgress: progress, financialYear: fy),
                isExport: false,
                provider: provider,
                financialYear: _salesReturnFy,
              ),
              deleteTap: () => widget.handleDelete(
                title: "Sales Returns",
                deleteAction: (p, fy) => p.deleteSalesReturnsRecords(fy),
                provider: provider,
                financialYear: _salesReturnFy,
              ),
            ),
            _dbActionTile(
              "Purchase Returns",
              "Purchase return logs",
              Icons.assignment_return_rounded,
              Colors.deepOrange.shade700,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Supplier", "Product", "Batch", "Pack", "Qty", "Total Amount", "Discount", "Ref Purchase", "Grand Total"],
              selectedFy: _purchaseReturnFy,
              availableFys: widget.availableFinancialYears,
              onFyChanged: (fy) => setState(() => _purchaseReturnFy = fy),
              onTap: () => widget.handleSync(
                title: "Export Purchase Returns",
                action: (p, path, progress, fy) => p.exportPurchaseReturnsToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _purchaseReturnFy,
              ),
              importTap: () => widget.handleSync(
                title: "Import Purchase Returns",
                action: (p, path, progress, fy) => p.importPurchaseReturnsFromExcel(path, onProgress: progress, financialYear: fy),
                isExport: false,
                provider: provider,
                financialYear: _purchaseReturnFy,
              ),
              deleteTap: () => widget.handleDelete(
                title: "Purchase Returns",
                deleteAction: (p, fy) => p.deletePurchaseReturnsRecords(fy),
                provider: provider,
                financialYear: _purchaseReturnFy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _dbActionTile(
              "Damage & Loss",
              "Inventory write-off logs",
              Icons.report_problem_rounded,
              Colors.red.shade700,
              btnLabel: "EXPORT",
              headings: ["Entry No", "Date", "Product", "Batch", "Pack", "Qty", "Reason", "Loss Value"],
              selectedFy: _damageFy,
              availableFys: widget.availableFinancialYears,
              onFyChanged: (fy) => setState(() => _damageFy = fy),
              onTap: () => widget.handleSync(
                title: "Export Damage & Loss",
                action: (p, path, progress, fy) => p.exportDamageToExcel(path, onProgress: progress, financialYear: fy),
                isExport: true,
                provider: provider,
                financialYear: _damageFy,
              ),
              importTap: () => widget.handleSync(
                title: "Import Damage & Loss",
                action: (p, path, progress, fy) => p.importDamageFromExcel(path, onProgress: progress, financialYear: fy),
                isExport: false,
                provider: provider,
                financialYear: _damageFy,
              ),
              deleteTap: () => widget.handleDelete(
                title: "Damage & Loss",
                deleteAction: (p, fy) => p.deleteDamageRecords(fy),
                provider: provider,
                financialYear: _damageFy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
        _buildImportSection(provider),
      ],
    );
  }

  Widget _buildImportSection(PharmacyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Legacy Software Migration", "One-time onboarding tool to import historical sales spreadsheets from older software."),
        const SizedBox(height: 24),
        Row(
          children: [
            _dbActionTile(
              "Import Sales History",
              "Upload past sales excel/csv records",
              Icons.cloud_download_rounded,
              Colors.teal,
              btnLabel: "IMPORT",
              onTap: () async {
                FilePickerResult? result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['xlsx', 'xls', 'csv'],
                );

                if (result != null && result.files.single.path != null) {
                  String filePath = result.files.single.path!;
                  if (!mounted) return;

                  final controller = StreamController<double>();
                  widget.showProgressDialog("Importing Sales History...", controller.stream);

                  Map<String, dynamic> res = await provider.importSalesFromExcel(
                    filePath,
                    onProgress: (p, statusText) {
                      if (!controller.isClosed) controller.add(p);
                    },
                  );

                  if (!mounted) return;
                  Navigator.pop(context); // Close progress dialog
                  controller.close();

                  if (res['success'] == true) {
                    await provider.loadFromDatabase();
                    widget.showSnackBar("Successfully imported ${res['invoices']} invoices (${res['items']} items) in seconds!");
                  } else {
                    widget.showSnackBar(res['message']?.toString() ?? "Import failed.", isError: true);
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _dbActionTile(
    String title,
    String sub,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
    String btnLabel = "GENERATE",
    VoidCallback? importTap,
    String importLabel = "IMPORT",
    VoidCallback? deleteTap,
    String deleteLabel = "DELETE",
    List<String>? headings,
    String? selectedFy,
    List<String>? availableFys,
    ValueChanged<String?>? onFyChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320, minWidth: 280),
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 30),
              if (headings != null)
                IconButton(
                  onPressed: () => _showExcelHeadingsDialog(title, headings),
                  icon: Icon(Icons.info_outline_rounded, size: 20, color: Colors.grey.shade400),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                  tooltip: "View Excel Headings",
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          if (availableFys != null && onFyChanged != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Text("FY:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedFy ?? "All Years",
                        isDense: true,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                        items: ["All Years", ...availableFys].map((fy) => DropdownMenuItem(value: fy, child: Text(fy))).toList(),
                        onChanged: onFyChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              if (onTap != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(btnLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
                  ),
                ),
              if (onTap != null && importTap != null) const SizedBox(width: 6),
              if (importTap != null)
                Expanded(
                  child: ElevatedButton(
                    onPressed: importTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(importLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
                  ),
                ),
              if (deleteTap != null) ...[
                if (onTap != null || importTap != null) const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton(
                    onPressed: deleteTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(deleteLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showExcelHeadingsDialog(String moduleTitle, List<String> headings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.table_chart_rounded, color: Colors.blue),
            const SizedBox(width: 10),
            Text("Expected Excel Headings: $moduleTitle"),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "When importing data from an Excel spreadsheet (.xlsx / .csv), ensure your column headers match these names (or map them during preview):",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: headings
                    .map((h) => Chip(
                          label: Text(h, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.blue.shade50,
                          side: BorderSide(color: Colors.blue.shade200),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }
}
