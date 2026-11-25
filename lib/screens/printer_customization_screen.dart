import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/erp_models.dart';
import '../services/esc_pos_printer_service.dart';
import '../utils/theme_constants.dart';
import '../utils/thermal_receipt_generator.dart';

enum DotMatrixPaperSize {
  inch8x11Standard, // 8.5" x 11" Full Sheet
  inch8x6Half, // 8.5" x 6" Half Sheet
  inch136Wide, // 136-Column Wide Sheet
}

class PrinterCustomizationScreen extends StatefulWidget {
  final bool useScaffold;
  const PrinterCustomizationScreen({super.key, this.useScaffold = true});

  @override
  State<PrinterCustomizationScreen> createState() => _PrinterCustomizationScreenState();
}

class _PrinterCustomizationScreenState extends State<PrinterCustomizationScreen> {
  // Editable Header Controllers for White-Labeling
  final TextEditingController _storeNameCtrl = TextEditingController(text: "SAHAKAR MEDICALS & SURGICALS");
  final TextEditingController _storeAddressCtrl = TextEditingController(text: "KALPETTA TOWN, WAYANAD");
  final TextEditingController _headerTitleCtrl = TextEditingController(text: "TAX INVOICE / CASH MEMO");
  final TextEditingController _returnPolicyCtrl = TextEditingController(text: "Medicines once sold will not be taken back");
  bool _showReturnPolicy = true;
  String _printMode = "dialog";

  DotMatrixPaperSize _paperSize = DotMatrixPaperSize.inch8x11Standard;
  String _selectedPrinterName = "TVS MSP 250 (80 Col)";
  final TextEditingController _thermalIpCtrl = TextEditingController(text: "192.168.1.100");
  int _columns = 80;
  int _linesPerPage = 66;

  // Real Windows installed printers
  List<Printer> _windowsPrinters = [];
  String? _selectedWindowsPrinter;
  bool _isLoadingPrinters = false;

  // Barcode Scanner Calibration
  final TextEditingController _barcodeScanCtrl = TextEditingController();
  final FocusNode _barcodeScanFocus = FocusNode();
  String _barcodeFeedback = "";
  DateTime? _firstCharTime;
  DateTime? _lastCharTime;
  int _charCount = 0;
  bool _isHardwareScanner = false;

  @override
  void initState() {
    super.initState();
    _loadPrinterPreferences();
    _fetchWindowsPrinters();
  }

  Future<void> _fetchWindowsPrinters() async {
    setState(() => _isLoadingPrinters = true);
    try {
      final printers = await Printing.listPrinters();
      if (!mounted) return;
      setState(() {
        _windowsPrinters = printers;
        _isLoadingPrinters = false;
        if (_selectedWindowsPrinter == null && printers.isNotEmpty) {
          final def = printers.where((p) => p.isDefault).firstOrNull ?? printers.first;
          _selectedWindowsPrinter = def.name;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingPrinters = false);
    }
  }

  Future<void> _loadPrinterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedPrinterName = prefs.getString('printer_model') ?? "TVS MSP 250 (80 Col)";
      _selectedWindowsPrinter = prefs.getString('preferred_printer_name');
      _columns = prefs.getInt('printer_columns') ?? 80;
      _linesPerPage = prefs.getInt('printer_lines') ?? 66;
      int paperSizeIndex = prefs.getInt('printer_paper_size') ?? DotMatrixPaperSize.inch8x11Standard.index;
      if (paperSizeIndex < DotMatrixPaperSize.values.length) {
        _paperSize = DotMatrixPaperSize.values[paperSizeIndex];
      }
      _storeNameCtrl.text = prefs.getString('store_name') ?? "SAHAKAR MEDICALS & SURGICALS";
      _storeAddressCtrl.text = prefs.getString('store_address') ?? "KALPETTA TOWN, WAYANAD";
      _headerTitleCtrl.text = prefs.getString('header_title') ?? "TAX INVOICE / CASH MEMO";
      _returnPolicyCtrl.text = prefs.getString('return_policy_text') ?? "Medicines once sold will not be taken back";
      _thermalIpCtrl.text = prefs.getString('thermal_printer_ip') ?? "192.168.1.100";
      _showReturnPolicy = prefs.getBool('show_return_policy') ?? true;
      _printMode = prefs.getString('printer_mode') ?? "dialog";
    });
  }

  Future<void> _savePrinterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_model', _selectedPrinterName);
    if (_selectedWindowsPrinter != null) {
      await prefs.setString('preferred_printer_name', _selectedWindowsPrinter!);
    }
    await prefs.setInt('printer_columns', _columns);
    await prefs.setInt('printer_lines', _linesPerPage);
    await prefs.setInt('printer_paper_size', _paperSize.index);
    await prefs.setString('thermal_printer_ip', _thermalIpCtrl.text.trim());
    await prefs.setString('store_name', _storeNameCtrl.text);
    await prefs.setString('store_address', _storeAddressCtrl.text);
    await prefs.setString('header_title', _headerTitleCtrl.text);
    await prefs.setString('return_policy_text', _returnPolicyCtrl.text);
    await prefs.setBool('show_return_policy', _showReturnPolicy);
    await prefs.setString('printer_mode', _printMode);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Printer profile and hardware mappings saved successfully!"), backgroundColor: Colors.green),
      );
    }
  }

  void _onPrinterSelected(String? printerName) {
    if (printerName == null) return;
    setState(() {
      _selectedPrinterName = printerName;
      if (printerName.contains("ESC/POS Thermal (80mm)")) {
        _columns = 48;
        _linesPerPage = 999;
      } else if (printerName.contains("ESC/POS Thermal (58mm)")) {
        _columns = 32;
        _linesPerPage = 999;
      } else if (printerName.contains("TVS MSP 250") || printerName.contains("Epson FX-890") || printerName.contains("Epson LQ-310")) {
        _paperSize = DotMatrixPaperSize.inch8x11Standard;
        _columns = 80;
        _linesPerPage = 66;
      } else if (printerName.contains("TVS MSP 345") || printerName.contains("Half Sheet")) {
        _paperSize = DotMatrixPaperSize.inch8x6Half;
        _columns = 80;
        _linesPerPage = 36;
      } else if (printerName.contains("TVS MSP 455") || printerName.contains("Epson FX-2190")) {
        _paperSize = DotMatrixPaperSize.inch136Wide;
        _columns = 136;
        _linesPerPage = 66;
      }
    });
  }

  void _onPaperSizeSelected(DotMatrixPaperSize? size) {
    if (size == null) return;
    setState(() {
      _paperSize = size;
      if (size == DotMatrixPaperSize.inch8x11Standard) {
        _columns = 80;
        _linesPerPage = 66;
      } else if (size == DotMatrixPaperSize.inch8x6Half) {
        _columns = 80;
        _linesPerPage = 36;
      } else if (size == DotMatrixPaperSize.inch136Wide) {
        _columns = 136;
        _linesPerPage = 66;
      }
    });
  }

  void _onBarcodeScanChanged(String val) {
    if (val.isEmpty) {
      _firstCharTime = null;
      _lastCharTime = null;
      _charCount = 0;
      return;
    }
    final now = DateTime.now();
    _firstCharTime ??= now;
    _lastCharTime = now;
    _charCount = val.length;
  }

  void _onBarcodeSubmitted(String barcode) {
    if (barcode.trim().isEmpty) return;
    final totalDurationMs = _lastCharTime != null && _firstCharTime != null
        ? _lastCharTime!.difference(_firstCharTime!).inMilliseconds
        : 999;
    final avgPerChar = _charCount > 1 ? (totalDurationMs / _charCount).round() : totalDurationMs;
    final isWedge = avgPerChar < 60;

    setState(() {
      _isHardwareScanner = isWedge;
      if (isWedge) {
        _barcodeFeedback = "✅ Hardware Scanner Verified: '$barcode' ($totalDurationMs ms, ~$avgPerChar ms/char) with [Enter] suffix.\nIdeal for hands-free 0-click POS barcode billing!";
      } else {
        _barcodeFeedback = "ℹ️ Scanned: '$barcode' in $totalDurationMs ms (~$avgPerChar ms/char).\nNote: If this was a hardware scanner, ensure USB HID high-speed burst mode is active.";
      }
    });
    _barcodeScanCtrl.clear();
    _firstCharTime = null;
    _lastCharTime = null;
    _barcodeScanFocus.requestFocus();
  }

  Future<void> _testPrintReceipt() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sampleInvoice = SaleInvoice(
        entryNo: "TEST-001",
        date: DateTime.now(),
        customerAcc: "Counter Test Patient",
        patient: "Counter Test Patient",
        doctor: "Dr. General Test",
        subTotal: 100.0,
        grandTotal: 112.0,
        items: [
          SaleItem(
            product: Product(
              id: "P1",
              name: "Paracetamol 650mg",
              batch: "TEST-B1",
              expiry: "2027-12",
              mrp: 20.0,
              salePrice: 20.0,
              gstPercent: 12.0,
            ),
            qty: 5,
            packin: 1,
            mrp: 20.0,
            sRate: 20.0,
            total: 100.0,
            gstPercent: 12.0,
            gstAmt: 12.0,
          ),
        ],
      );

      final company = CompanyProfile(
        name: _storeNameCtrl.text.trim().isNotEmpty ? _storeNameCtrl.text.trim() : "SAHAKAR MEDICALS",
        address: _storeAddressCtrl.text.trim(),
        tagline: _headerTitleCtrl.text.trim(),
      );

      // Direct TCP Socket if Network Thermal IP is specified
      if (_thermalIpCtrl.text.trim().isNotEmpty && _thermalIpCtrl.text.contains('.')) {
        final bytes = EscPosPrinterService.instance.generateReceiptBytes(
          company: company,
          invoiceNo: sampleInvoice.entryNo,
          dateStr: "24/11/2026",
          patientName: sampleInvoice.customerAcc,
          doctorName: "Dr. Store Test",
          items: [
            {'name': 'Paracetamol 650mg', 'batch': 'TEST-B1', 'qty': '5', 'rate': 20.0, 'amount': 100.0}
          ],
          totalAmount: 112.0,
          totalDiscount: 0.0,
          gstTotal: 12.0,
          paymentMode: "Cash",
        );
        final success = await EscPosPrinterService.instance.printDirectTcp(
          bytes: bytes,
          ipAddress: _thermalIpCtrl.text.trim(),
        );
        if (success && mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text("✅ Direct TCP receipt sent to thermal printer!"), backgroundColor: Colors.green),
          );
          return;
        }
      }

      // Windows Printer Spooler Fallback
      Printer? targetPrinter;
      if (_selectedWindowsPrinter != null && _windowsPrinters.isNotEmpty) {
        try {
          targetPrinter = _windowsPrinters.firstWhere((p) => p.name == _selectedWindowsPrinter);
        } catch (_) {}
      }

      final bytes = await ThermalReceiptGenerator.buildThermalReceipt(sampleInvoice, company);
      if (targetPrinter != null) {
        await Printing.directPrintPdf(
          printer: targetPrinter,
          onLayout: (_) async => bytes,
          name: 'Test_Receipt',
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: 'Test_Receipt',
        );
      }

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text("✅ Test print dispatched to printer queue!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text("Test print failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _testCashDrawerPulse() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_thermalIpCtrl.text.trim().isNotEmpty && _thermalIpCtrl.text.contains('.')) {
        final success = await EscPosPrinterService.instance.printDirectTcp(
          bytes: Uint8List.fromList(EscPosPrinterService.cmdCashDrawer),
          ipAddress: _thermalIpCtrl.text.trim(),
        );
        if (success && mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text("✅ Cash drawer pulse command sent via TCP!"), backgroundColor: Colors.green),
          );
          return;
        }
      }

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("ℹ️ Note: Standard Windows receipt printers automatically trigger the cash drawer kick via RJ11 pulse upon printing an invoice."),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text("Cash drawer test failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storeAddressCtrl.dispose();
    _headerTitleCtrl.dispose();
    _returnPolicyCtrl.dispose();
    _thermalIpCtrl.dispose();
    _barcodeScanCtrl.dispose();
    _barcodeScanFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useScaffold) {
      return Scaffold(
        backgroundColor: AppColors.of(context).background,
        appBar: AppBar(
          title: const Text("Hardware & Peripheral Calibration Hub", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: _buildBody(),
      );
    }
    return _buildBody();
  }

  Widget _buildBody() {
    return Row(
      children: [
        // LEFT PANEL: Hardware Configuration & Testing
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _sectionTitle("Windows Installed Printers (Auto-Detected)"),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedWindowsPrinter,
                      decoration: _inputDecoration("Primary Counter Printer"),
                      items: _windowsPrinters.map((p) {
                        return DropdownMenuItem<String>(
                          value: p.name,
                          child: Text(
                            "${p.name}${p.isDefault ? ' (Default)' : ''}",
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedWindowsPrinter = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isLoadingPrinters ? null : _fetchWindowsPrinters,
                    icon: _isLoadingPrinters
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, color: AppColors.primary),
                    tooltip: "Rescan Connected Printers",
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _sectionTitle("Hardware Diagnostics & Peripheral Testing"),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Instant Hardware Verification:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _testPrintReceipt,
                          icon: const Icon(Icons.print, size: 16),
                          label: const Text("TEST PRINT RECEIPT"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _testCashDrawerPulse,
                          icon: const Icon(Icons.meeting_room_rounded, size: 16),
                          label: const Text("TEST CASH DRAWER"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _sectionTitle("USB Barcode Scanner Calibration"),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, color: Colors.amber.shade900, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Scan any medicine barcode below to verify wedge burst speed:",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _barcodeScanCtrl,
                      focusNode: _barcodeScanFocus,
                      decoration: InputDecoration(
                        hintText: "Click here & scan barcode with USB scanner...",
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        prefixIcon: const Icon(Icons.barcode_reader, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: _onBarcodeScanChanged,
                      onSubmitted: _onBarcodeSubmitted,
                    ),
                    if (_barcodeFeedback.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isHardwareScanner ? Colors.green.shade50 : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _isHardwareScanner ? Colors.green.shade300 : Colors.blue.shade300),
                        ),
                        child: Text(
                          _barcodeFeedback,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isHardwareScanner ? Colors.green.shade900 : Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _sectionTitle("Pharmacy Header Customization (White-Label)"),
              TextFormField(
                controller: _storeNameCtrl,
                onChanged: (v) => setState(() {}),
                decoration: _inputDecoration("Store Name"),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _storeAddressCtrl,
                onChanged: (v) => setState(() {}),
                decoration: _inputDecoration("Store Address / Location"),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _headerTitleCtrl,
                onChanged: (v) => setState(() {}),
                decoration: _inputDecoration("Invoice Title (e.g. Tax Invoice)"),
              ),
              const SizedBox(height: 16),
              _sectionTitle("Invoice Footer Notice / Return Policy"),
              SwitchListTile(
                title: const Text("Show Return Policy Notice on Bill", style: TextStyle(fontSize: 12)),
                value: _showReturnPolicy,
                onChanged: (v) => setState(() => _showReturnPolicy = v),
              ),
              if (_showReturnPolicy) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _returnPolicyCtrl,
                  onChanged: (v) => setState(() {}),
                  decoration: _inputDecoration("Return Policy Text"),
                ),
              ],
              const SizedBox(height: 24),

              _sectionTitle("Default Print Mode (Auto-Print Behavior)"),
              DropdownButtonFormField<String>(
                initialValue: _printMode,
                decoration: _inputDecoration("Print Behavior on Print Button Click"),
                items: const [
                  DropdownMenuItem(value: "dialog", child: Text("Ask Every Time (Show Format Dialog)", style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: "thermal", child: Text("Auto-Print Thermal Receipt (80mm)", style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: "a4", child: Text("Auto-Print A4 Graphical Invoice", style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: "dot_matrix", child: Text("Auto-Print Dot Matrix Bill", style: TextStyle(fontSize: 12))),
                ],
                onChanged: (v) => setState(() => _printMode = v ?? "dialog"),
              ),
              const SizedBox(height: 24),

              _sectionTitle("Hardware Mapping (Paper Size & Printer Model)"),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // LEFT: Paper Size Dropdown
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<DotMatrixPaperSize>(
                      initialValue: _paperSize,
                      decoration: _inputDecoration("Paper Size"),
                      items: const [
                        DropdownMenuItem(
                          value: DotMatrixPaperSize.inch8x11Standard,
                          child: Text("8.5\" x 11\" (Full)", style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: DotMatrixPaperSize.inch8x6Half,
                          child: Text("8.5\" x 6\" (Half)", style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: DotMatrixPaperSize.inch136Wide,
                          child: Text("136-Col Wide", style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      onChanged: _onPaperSizeSelected,
                    ),
                  ),
                  Text("OR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey.withValues(alpha: 0.5))),
                  // RIGHT: Common Printer Names Dropdown
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedPrinterName,
                      decoration: _inputDecoration("Printer Model"),
                      items: const [
                        DropdownMenuItem(value: "ESC/POS Thermal (80mm)", child: Text("ESC/POS Thermal (80mm)", style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: "ESC/POS Thermal (58mm)", child: Text("ESC/POS Thermal (58mm)", style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: "TVS MSP 250 (80 Col)", child: Text("TVS MSP 250", style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: "Epson LQ-310 (80 Col)", child: Text("Epson LQ-310", style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: "Epson FX-890 (80 Col)", child: Text("Epson FX-890", style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: "TVS MSP 455 (Wide)", child: Text("TVS MSP 455 (Wide)", style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: "Epson FX-2190 (Wide)", child: Text("Epson FX-2190 (Wide)", style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: _onPrinterSelected,
                    ),
                  ),
                ],
              ),
              if (_selectedPrinterName.contains("Thermal")) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _thermalIpCtrl,
                  decoration: _inputDecoration("Thermal Printer Network IP (Port 9100)"),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey("cols_$_columns"),
                      initialValue: _columns.toString(),
                      decoration: _inputDecoration("Print Columns"),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() => _columns = int.tryParse(v) ?? 80),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey("lines_$_linesPerPage"),
                      initialValue: _linesPerPage.toString(),
                      decoration: _inputDecoration("Lines/Page"),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() => _linesPerPage = int.tryParse(v) ?? 66),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              ElevatedButton.icon(
                onPressed: _savePrinterPreferences,
                icon: const Icon(Icons.save),
                label: const Text("Save Hardware Configuration"),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
              ),
            ],
          ),
        ),

        // RIGHT PANEL: Live Monospace Print Preview
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 8),
                    Text("PREVIEW: $_selectedPrinterName ($_columns Cols x $_linesPerPage Rows)",
                        style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(color: Colors.grey),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Text(
                        _generatePreviewText(_columns),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    );
  }

  String _generatePreviewText(int cols) {
    String line = "-" * cols;
    String storeName = _storeNameCtrl.text.toUpperCase();
    String storeAddress = _storeAddressCtrl.text.toUpperCase();
    String headerTitle = _headerTitleCtrl.text.toUpperCase();

    return """
$line
${storeName.padLeft((cols + storeName.length) ~/ 2)}
${storeAddress.padLeft((cols + storeAddress.length) ~/ 2)}
${headerTitle.padLeft((cols + headerTitle.length) ~/ 2)}
$line
INV NO: 1042                     DATE: 31/07/2026
PATIENT: Jiyad                   DOCTOR: Dr. General
$line
SL HSN    PRODUCT / MFR           BATCH   EXP   QTY   MRP     DISC    RATE    TOTAL
$line
1  3004   PARACETAMOL 650MG       B124    08/28 10    20.00   10.00   19.00   190.00
          [MFR: CIPLA LTD]
2  3004   AMOXICILLIN 500CAP      AX99    12/27 2    150.00    0.00  150.00   300.00
          [MFR: GSK PHARMA]
3  3004   PAN-D CAPSULES          P202    04/28 5    220.00  110.00  198.00   990.00
          [MFR: SUN PHARMA]
$line
                                 SUBTOTAL:    1480.00
                                 TOTAL DISC:   120.00
                                 GST (12%):    177.60
                                 GRAND TOTAL: 1657.60
$line
         THANK YOU! VISIT AGAIN - COMPUTERIZED BILLING
$line
TIME: 08:55 PM                                             PHARMACIST SIGNATURE

[PERFORATION / FORM FEED BREAK]
""";
  }
}
