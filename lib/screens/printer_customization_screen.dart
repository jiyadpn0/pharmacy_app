import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme_constants.dart';

enum DotMatrixPaperSize {
  inch_8x11_standard,  // 8.5" x 11" Full Sheet
  inch_8x6_half,       // 8.5" x 6" Half Sheet
  inch_136_wide,       // 136-Column Wide Sheet
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

  DotMatrixPaperSize _paperSize = DotMatrixPaperSize.inch_8x11_standard;
  String _selectedPrinterName = "TVS MSP 250 (80 Col)";
  int _columns = 80;
  int _linesPerPage = 66;

  @override
  void initState() {
    super.initState();
    _loadPrinterPreferences();
  }

  Future<void> _loadPrinterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedPrinterName = prefs.getString('printer_model') ?? "TVS MSP 250 (80 Col)";
      _columns = prefs.getInt('printer_columns') ?? 80;
      _linesPerPage = prefs.getInt('printer_lines') ?? 66;
      int paperSizeIndex = prefs.getInt('printer_paper_size') ?? DotMatrixPaperSize.inch_8x11_standard.index;
      if (paperSizeIndex < DotMatrixPaperSize.values.length) {
        _paperSize = DotMatrixPaperSize.values[paperSizeIndex];
      }
      _storeNameCtrl.text = prefs.getString('store_name') ?? "SAHAKAR MEDICALS & SURGICALS";
      _storeAddressCtrl.text = prefs.getString('store_address') ?? "KALPETTA TOWN, WAYANAD";
      _headerTitleCtrl.text = prefs.getString('header_title') ?? "TAX INVOICE / CASH MEMO";
    });
  }

  Future<void> _savePrinterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_model', _selectedPrinterName);
    await prefs.setInt('printer_columns', _columns);
    await prefs.setInt('printer_lines', _linesPerPage);
    await prefs.setInt('printer_paper_size', _paperSize.index);
    await prefs.setString('store_name', _storeNameCtrl.text);
    await prefs.setString('store_address', _storeAddressCtrl.text);
    await prefs.setString('header_title', _headerTitleCtrl.text);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Printer profile saved successfully!"), backgroundColor: Colors.green),
      );
    }
  }

  // Mapping common Kerala pharmacy printers to specs
  void _onPrinterSelected(String? printerName) {
    if (printerName == null) return;
    setState(() {
      _selectedPrinterName = printerName;
      if (printerName.contains("TVS MSP 250") || printerName.contains("Epson FX-890") || printerName.contains("Epson LQ-310")) {
        _paperSize = DotMatrixPaperSize.inch_8x11_standard;
        _columns = 80;
        _linesPerPage = 66;
      } else if (printerName.contains("TVS MSP 345") || printerName.contains("Half Sheet")) {
        _paperSize = DotMatrixPaperSize.inch_8x6_half;
        _columns = 80;
        _linesPerPage = 36;
      } else if (printerName.contains("TVS MSP 455") || printerName.contains("Epson FX-2190")) {
        _paperSize = DotMatrixPaperSize.inch_136_wide;
        _columns = 136;
        _linesPerPage = 66;
      }
    });
  }

  void _onPaperSizeSelected(DotMatrixPaperSize? size) {
    if (size == null) return;
    setState(() {
      _paperSize = size;
      if (size == DotMatrixPaperSize.inch_8x11_standard) {
        _columns = 80;
        _linesPerPage = 66;
      } else if (size == DotMatrixPaperSize.inch_8x6_half) {
        _columns = 80;
        _linesPerPage = 36;
      } else if (size == DotMatrixPaperSize.inch_136_wide) {
        _columns = 136;
        _linesPerPage = 66;
      }
    });
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storeAddressCtrl.dispose();
    _headerTitleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useScaffold) {
      return Scaffold(
        backgroundColor: AppColors.of(context).background,
        appBar: AppBar(
          title: const Text("Universal Printer Customization Hub", style: TextStyle(fontWeight: FontWeight.bold)),
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
        // LEFT PANEL: Configuration & Dynamic Headers
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
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
                          value: DotMatrixPaperSize.inch_8x11_standard,
                          child: Text("8.5\" x 11\" (Full)", style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: DotMatrixPaperSize.inch_8x6_half,
                          child: Text("8.5\" x 6\" (Half)", style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: DotMatrixPaperSize.inch_136_wide,
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
                label: const Text("Save Printer Profile"),
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
SL ITEM NAME / MFR          BATCH    EXP   QTY   DISC   MRP    TOTAL
$line
1  PARACETAMOL 650MG        B124     08/28 10   10.00  20.00  190.00
   [MFR: CIPLA LTD]
2  AMOXICILLIN 500CAP       AX99     12/27 2     0.00 150.00  300.00
   [MFR: GSK PHARMA]
3  PAN-D CAPSULES           P202     04/28 5   110.00 220.00  990.00
   [MFR: SUN PHARMA]
$line
                                 SUBTOTAL:    1480.00
                                 TOTAL DISC:   120.00
                                 GST (12%):    177.60
                                 GRAND TOTAL: 1657.60
$line
         THANK YOU! VISIT AGAIN - COMPUTERIZED BILLING
$line
\n\n[PERFORATION / FORM FEED BREAK]
""";
  }
}
