import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../providers/pharmacy_provider.dart';

class PdfVisualMapperDialog extends StatefulWidget {
  final String currentSupplier;
  final String? initialFilePath;
  final ImportMapping? initialMapping;
  final bool isEditMode;
  final int? mappingIndex;
  final Function(ImportMapping, List<String>, List<List<dynamic>>, bool) onImportReady;

  const PdfVisualMapperDialog({
    super.key,
    required this.currentSupplier,
    this.initialFilePath,
    this.initialMapping,
    this.isEditMode = false,
    this.mappingIndex,
    required this.onImportReady,
  });

  @override
  State<PdfVisualMapperDialog> createState() => _PdfVisualMapperDialogState();
}

class _PdfPageData {
  final int pageNumber;
  final double width;
  final double height;
  final List<TextWord> words;

  _PdfPageData({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.words,
  });
}

class _FieldColumnBoundary {
  final String field;
  double left;
  double right;
  final Color color;

  _FieldColumnBoundary({
    required this.field,
    required this.left,
    required this.right,
    required this.color,
  });
}

class _PdfVisualMapperDialogState extends State<PdfVisualMapperDialog> {
  bool _isLoading = false;
  String? _selectedFilePath;

  List<_PdfPageData> _pages = [];
  int _currentPageIdx = 0;

  double _topBound = 180.0;
  double _bottomBound = 650.0;

  final Map<String, _FieldColumnBoundary> _fieldBoundaries = {};
  String? _activeEditingField;

  double _canvasScale = 1.25;
  bool _showFloatingTags = true;

  final List<String> allHeadings = [
    'Product', 'Batch', 'Exp', 'Qty', 'Fqty', 'Packing',
    'Prate', 'Mrp', 'Product Code',
    'Disc %', 'Disc Amt',
    'GST %', 'GST Amt',
    'CGST %', 'SGST %',
    'CGST Amt', 'SGST Amt',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialFilePath != null && widget.initialFilePath!.isNotEmpty) {
        _parsePdfFromPath(widget.initialFilePath!);
      } else {
        _pickAndParsePdf();
      }
    });
  }

  bool _isFieldDisabled(String field) {
    if (field == 'Disc %' && _fieldBoundaries.containsKey('Disc Amt')) return true;
    if (field == 'Disc Amt' && _fieldBoundaries.containsKey('Disc %')) return true;

    if (field == 'GST %') {
      if (_fieldBoundaries.containsKey('GST Amt') ||
          _fieldBoundaries.containsKey('CGST %') || _fieldBoundaries.containsKey('SGST %') ||
          _fieldBoundaries.containsKey('CGST Amt') || _fieldBoundaries.containsKey('SGST Amt')) {
        return true;
      }
    }

    if (field == 'GST Amt') {
      if (_fieldBoundaries.containsKey('GST %') ||
          _fieldBoundaries.containsKey('CGST %') || _fieldBoundaries.containsKey('SGST %') ||
          _fieldBoundaries.containsKey('CGST Amt') || _fieldBoundaries.containsKey('SGST Amt')) {
        return true;
      }
    }

    if (field == 'CGST %' || field == 'SGST %') {
      if (_fieldBoundaries.containsKey('GST %') ||
          _fieldBoundaries.containsKey('GST Amt') ||
          _fieldBoundaries.containsKey('CGST Amt') || _fieldBoundaries.containsKey('SGST Amt')) {
        return true;
      }
    }

    if (field == 'CGST Amt' || field == 'SGST Amt') {
      if (_fieldBoundaries.containsKey('GST %') ||
          _fieldBoundaries.containsKey('GST Amt') ||
          _fieldBoundaries.containsKey('CGST %') || _fieldBoundaries.containsKey('SGST %')) {
        return true;
      }
    }

    return false;
  }

  Color _getFieldColor(String field) {
    switch (field) {
      case 'Product': return Colors.blue.shade700;
      case 'Batch': return Colors.orange.shade800;
      case 'Exp': return Colors.purple.shade700;
      case 'Qty': return Colors.teal.shade700;
      case 'Fqty': return Colors.green.shade700;
      case 'Packing': return Colors.cyan.shade800;
      case 'Prate': return Colors.red.shade700;
      case 'Mrp': return Colors.deepOrange.shade800;
      case 'Disc %': return Colors.amber.shade900;
      case 'Disc Amt': return Colors.amber.shade700;
      case 'GST %': return Colors.indigo.shade700;
      case 'GST Amt': return Colors.indigo.shade900;
      case 'CGST %': return Colors.indigo.shade500;
      case 'SGST %': return Colors.indigo.shade400;
      case 'CGST Amt': return Colors.blueGrey.shade700;
      case 'SGST Amt': return Colors.blueGrey.shade600;
      case 'Product Code': return Colors.brown.shade700;
      default: return Colors.blueGrey.shade700;
    }
  }

  Future<void> _pickAndParsePdf() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;
    _parsePdfFromPath(result.files.single.path!);
  }

  Future<void> _parsePdfFromPath(String filePath) async {
    setState(() {
      _isLoading = true;
      _selectedFilePath = filePath;
      _pages.clear();
      _currentPageIdx = 0;
      _fieldBoundaries.clear();
      _activeEditingField = null;
    });

    try {
      final bytes = File(_selectedFilePath!).readAsBytesSync();
      PdfDocument document = PdfDocument(inputBytes: bytes);
      PdfTextExtractor extractor = PdfTextExtractor(document);

      List<_PdfPageData> parsedPages = [];

      for (int p = 0; p < document.pages.count; p++) {
        final page = document.pages[p];
        List<TextLine> textLines = extractor.extractTextLines(startPageIndex: p, endPageIndex: p);
        List<TextWord> words = [];
        for (var line in textLines) {
          for (var word in line.wordCollection) {
            if (word.text.trim().isNotEmpty) words.add(word);
          }
        }

        parsedPages.add(_PdfPageData(
          pageNumber: p + 1,
          width: page.size.width,
          height: page.size.height,
          words: words,
        ));
      }

      document.dispose();

      if (parsedPages.isEmpty || parsedPages.first.words.isEmpty) {
        throw "No selectable text found in this PDF.";
      }

      setState(() {
        _pages = parsedPages;
        _restoreSavedOrAutoLayout();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _restoreSavedOrAutoLayout() {
    if (_pages.isEmpty) return;
    final page = _pages[_currentPageIdx];

    ImportMapping? targetMapping = widget.initialMapping;
    if (targetMapping == null && widget.currentSupplier.isNotEmpty) {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      targetMapping = p.importMappings.cast<ImportMapping?>().firstWhere(
            (m) => m?.name.toLowerCase().trim() == "${widget.currentSupplier} - pdf".toLowerCase().trim() ||
            m?.name.toLowerCase().trim() == widget.currentSupplier.toLowerCase().trim(),
        orElse: () => null,
      );
    }

    if (targetMapping != null && targetMapping.fieldMappings.containsKey('__PDF_LAYOUT__')) {
      try {
        final rawJson = targetMapping.fieldMappings['__PDF_LAYOUT__']!.first;
        final layout = jsonDecode(rawJson) as Map<String, dynamic>;

        _topBound = (layout['top'] as num?)?.toDouble() ?? (page.height * 0.22);
        _bottomBound = (layout['bottom'] as num?)?.toDouble() ?? (page.height * 0.75);

        if (layout.containsKey('field_bounds')) {
          final boundsMap = layout['field_bounds'] as Map<String, dynamic>;
          boundsMap.forEach((field, coords) {
            String cleanField = field;
            if (cleanField == 'DisPer') cleanField = 'Disc %';
            if (cleanField == 'TaxPer (Total)') cleanField = 'GST %';

            _fieldBoundaries[cleanField] = _FieldColumnBoundary(
              field: cleanField,
              left: (coords['left'] as num).toDouble(),
              right: (coords['right'] as num).toDouble(),
              color: _getFieldColor(cleanField),
            );
          });
        }

        if (_fieldBoundaries.isNotEmpty) {
          _activeEditingField = _fieldBoundaries.keys.first;
        }
        return;
      } catch (e) {
        debugPrint("Error restoring layout: $e");
      }
    }

    _topBound = page.height * 0.22;
    _bottomBound = page.height * 0.75;
  }

  void _onHeadingClicked(String field) {
    if (_isFieldDisabled(field)) return;
    if (_pages.isEmpty) return;
    final page = _pages[_currentPageIdx];

    setState(() {
      _activeEditingField = field;

      if (!_fieldBoundaries.containsKey(field)) {
        double defaultWidth = field == 'Product' ? 140.0 : 55.0;
        double defaultLeft = 30.0;

        if (_fieldBoundaries.isNotEmpty) {
          double maxRight = _fieldBoundaries.values.map((b) => b.right).reduce(max);
          if (maxRight + defaultWidth < page.width - 20) {
            defaultLeft = maxRight + 6.0;
          }
        }

        _fieldBoundaries[field] = _FieldColumnBoundary(
          field: field,
          left: defaultLeft,
          right: (defaultLeft + defaultWidth).clamp(defaultLeft + 15.0, page.width - 10.0),
          color: _getFieldColor(field),
        );
      }
    });
  }

  void _removeHeading(String field) {
    setState(() {
      _fieldBoundaries.remove(field);
      if (_activeEditingField == field) {
        _activeEditingField = _fieldBoundaries.isNotEmpty ? _fieldBoundaries.keys.first : null;
      }
    });
  }

  // --- SMART 2-WAY ROW STITCHING & NORMALIZATION ---
  List<Map<String, String>> _extractStructuredRows() {
    if (_pages.isEmpty || _fieldBoundaries.isEmpty) return [];

    List<Map<String, String>> extractedRows = [];
    final sortedFields = _fieldBoundaries.values.toList()..sort((a, b) => a.left.compareTo(b.left));

    double parseVal(String? s) => double.tryParse((s ?? "").replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

    for (int pageIdx = 0; pageIdx < _pages.length; pageIdx++) {
      var page = _pages[pageIdx];
      String pageAllText = page.words.map((w) => w.text.toLowerCase()).join(' ');

      // Stop immediately if Page 2/3 is a promo/scheme table instead of items
      if (pageIdx > 0) {
        bool isProductTable = pageAllText.contains('item description') ||
            pageAllText.contains('description of goods') ||
            (pageAllText.contains('hsn') && pageAllText.contains('batch'));
        if (!isProductTable || pageAllText.contains('initiative name') || pageAllText.contains('free product')) {
          break;
        }
      }

      // Filter words strictly within the red/green boundaries
      final validWords = page.words.where((w) {
        double midY = w.bounds.top + (w.bounds.height / 2.0);
        return midY >= _topBound && midY <= _bottomBound;
      }).toList();

      if (validWords.isEmpty) continue;

      Map<int, List<TextWord>> rowsMap = {};
      for (var w in validWords) {
        int ySnap = (w.bounds.top / 7.0).round() * 7;
        rowsMap.putIfAbsent(ySnap, () => []).add(w);
      }

      var sortedY = rowsMap.keys.toList()..sort();
      Map<String, String>? pendingItem;

      for (var y in sortedY) {
        var lineWords = rowsMap[y]!..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
        String fullLine = lineWords.map((w) => w.text).join(' ').trim().toLowerCase();

        // Stop on footer / total lines
        if (fullLine.startsWith('total') ||
            fullLine.contains('grand total') ||
            fullLine.contains('initiative') ||
            fullLine.contains('terms and conditions') ||
            fullLine.contains('acknowledgement')) {
          break;
        }

        Map<String, String> lineData = {};
        for (var b in sortedFields) {
          List<String> fieldWords = [];
          for (var word in lineWords) {
            if (word.text == '|') continue;
            double wCenter = word.bounds.left + (word.bounds.width / 2.0);
            if (wCenter >= b.left && wCenter <= b.right) {
              fieldWords.add(word.text.trim());
            }
          }
          lineData[b.field] = fieldWords.join(' ').trim();
        }

        String prod = (lineData['Product'] ?? '').trim();

        if (RegExp(r'^\d+$').hasMatch(prod)) {
          List<String> textWords = [];
          for (var word in lineWords) {
            String wt = word.text.trim();
            if (wt == '|' || wt == prod) continue;
            if (RegExp(r'[a-zA-Z]').hasMatch(wt) &&
                wt.toLowerCase() != 'total' &&
                wt.toLowerCase() != 'subtotal' &&
                !wt.toLowerCase().contains('gst') &&
                !wt.toLowerCase().contains('exp') &&
                !wt.toLowerCase().contains('batch')) {
              textWords.add(wt);
            }
          }

          if (textWords.isNotEmpty) {
            String realName = textWords.join(' ').trim();
            if (lineData['Product Code'] == null || lineData['Product Code']!.isEmpty) {
              lineData['Product Code'] = prod;
            }
            lineData['Product'] = realName;
            prod = realName;
          }
        }

        // Skip promo scheme codes
        if (prod.startsWith('LTR') || prod.startsWith('LSS') || prod.contains('Buy Any') || prod.contains('Buy 1 pc')) {
          continue;
        }

        double lineQty = parseVal(lineData['Qty']);
        double linePrate = parseVal(lineData['Prate']);
        double lineMrp = parseVal(lineData['Mrp']);

        bool lineHasNumbers = (lineQty > 0) || (linePrate > 0) || (lineMrp > 0);
        bool lineHasIdentity = prod.isNotEmpty && prod.length >= 2;

        if (pendingItem == null) {
          if (lineHasNumbers || lineHasIdentity) {
            pendingItem = Map<String, String>.from(lineData);
          }
        } else {
          double pendingQty = parseVal(pendingItem['Qty']);
          double pendingPrate = parseVal(pendingItem['Prate']);
          double pendingMrp = parseVal(pendingItem['Mrp']);
          bool pendingHasNumbers = (pendingQty > 0) || (pendingPrate > 0) || (pendingMrp > 0);

          if (!pendingHasNumbers && lineHasNumbers) {
            if (prod.isNotEmpty) {
              pendingItem['Product'] = "${pendingItem['Product']} $prod".trim();
            }
            lineData.forEach((k, v) {
              if (v.isNotEmpty && (pendingItem![k] == null || pendingItem[k]!.isEmpty || pendingItem[k] == "0")) {
                pendingItem[k] = v;
              }
            });
          } else if (pendingHasNumbers && !lineHasNumbers) {
            if (prod.isNotEmpty) {
              pendingItem['Product'] = "${pendingItem['Product']} $prod".trim();
            }
            if ((lineData['Batch'] ?? '').isNotEmpty && (pendingItem['Batch'] ?? '').isEmpty) {
              pendingItem['Batch'] = lineData['Batch']!;
            }
            if ((lineData['Exp'] ?? '').isNotEmpty && (pendingItem['Exp'] ?? '').isEmpty) {
              pendingItem['Exp'] = lineData['Exp']!;
            }
          } else {
            extractedRows.add(_normalizeCalculations(pendingItem));
            pendingItem = Map<String, String>.from(lineData);
          }
        }
      }

      if (pendingItem != null) {
        extractedRows.add(_normalizeCalculations(pendingItem));
        pendingItem = null;
      }

      // Check if page contains Total anywhere below top bound
      bool hasTotalOnPage = page.words.any((w) =>
          w.bounds.top >= _topBound &&
          (w.text.toLowerCase() == 'total' || w.text.toLowerCase() == 'grand total'));
      if (hasTotalOnPage) {
        break; // Stop further page scans
      }
    }

    return extractedRows;
  }

  Map<String, String> _normalizeCalculations(Map<String, String> rowItem) {
    double parseVal(String? s) => double.tryParse((s ?? "").replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

    // Smart Product Name & Code swap / fallback:
    String prodName = (rowItem['Product'] ?? '').trim();
    String prodCode = (rowItem['Product Code'] ?? '').trim();

    bool prodIsNumeric = RegExp(r'^\d+$').hasMatch(prodName);
    bool codeHasLetters = RegExp(r'[a-zA-Z]').hasMatch(prodCode);

    if (prodIsNumeric && codeHasLetters) {
      rowItem['Product'] = prodCode;
      rowItem['Product Code'] = prodName;
      prodName = prodCode;
      prodCode = rowItem['Product Code']!;
      prodIsNumeric = false;
    }

    if (prodIsNumeric || prodName.isEmpty) {
      String bestTextCandidate = "";
      for (var entry in rowItem.entries) {
        if (entry.key == 'Qty' || entry.key == 'Fqty' || entry.key == 'Prate' || entry.key == 'Mrp' || entry.key == 'Disc %' || entry.key == 'GST %') continue;
        String val = entry.value.trim();
        if (RegExp(r'[a-zA-Z]').hasMatch(val)) {
          if (bestTextCandidate.isEmpty || val.length > bestTextCandidate.length) {
            bestTextCandidate = val;
          }
        }
      }
      if (bestTextCandidate.isNotEmpty) {
        if (prodName.isNotEmpty && prodIsNumeric && (prodCode.isEmpty || prodCode == prodName)) {
          rowItem['Product Code'] = prodName;
        }
        rowItem['Product'] = bestTextCandidate;
      }
    }

    double qty = parseVal(rowItem['Qty']);
    double prate = parseVal(rowItem['Prate']);
    double mrp = parseVal(rowItem['Mrp']);
    double gross = (prate > 0 ? prate : mrp) * (qty > 0 ? qty : 1.0);

    if (rowItem.containsKey('Disc Amt') && !rowItem.containsKey('Disc %')) {
      double discAmt = parseVal(rowItem['Disc Amt']);
      if (gross > 0 && discAmt > 0) {
        rowItem['Disc %'] = ((discAmt / gross) * 100.0).toStringAsFixed(2);
      } else {
        rowItem['Disc %'] = "0";
      }
    }

    if (!rowItem.containsKey('GST %')) {
      if (rowItem.containsKey('CGST %') || rowItem.containsKey('SGST %')) {
        double cgst = parseVal(rowItem['CGST %']);
        double sgst = parseVal(rowItem['SGST %']);
        if (cgst > 0 && sgst > 0) {
          rowItem['GST %'] = (cgst + sgst).toStringAsFixed(2);
        } else if (cgst > 0) {
          rowItem['GST %'] = (cgst * 2).toStringAsFixed(2);
        } else if (sgst > 0) {
          rowItem['GST %'] = (sgst * 2).toStringAsFixed(2);
        }
      } else if (rowItem.containsKey('GST Amt')) {
        double gstAmt = parseVal(rowItem['GST Amt']);
        if (gross > 0 && gstAmt > 0) {
          rowItem['GST %'] = ((gstAmt / gross) * 100.0).toStringAsFixed(2);
        }
      } else if (rowItem.containsKey('CGST Amt') || rowItem.containsKey('SGST Amt')) {
        double cgstAmt = parseVal(rowItem['CGST Amt']);
        double sgstAmt = parseVal(rowItem['SGST Amt']);
        double totalGstAmt = cgstAmt + sgstAmt;
        if (gross > 0 && totalGstAmt > 0) {
          rowItem['GST %'] = ((totalGstAmt / gross) * 100.0).toStringAsFixed(2);
        }
      }
    }

    return rowItem;
  }

  void _confirmAndSaveTemplate() async {
    final rows = _extractStructuredRows();

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No items found inside the selected columns!"), backgroundColor: Colors.red),
      );
      return;
    }

    final List<String> standardColumns = [
      'Product', 'Batch', 'Exp', 'Packing', 'Qty', 'Fqty',
      'Prate', 'Mrp', 'DisPer', 'TaxPer (Total)', 'Product Code'
    ];

    List<List<dynamic>> finalDataRows = [];
    for (var r in rows) {
      finalDataRows.add(standardColumns.map((col) {
        String val = "";
        if (col == 'DisPer') {
          val = r['Disc %'] ?? r['Disc Amt'] ?? "";
        } else if (col == 'TaxPer (Total)') {
          val = r['GST %'] ?? r['GST Amt'] ?? "";
        } else {
          val = r[col] ?? "";
        }

        if (val.trim().isEmpty) {
          if (col == 'Fqty' || col == 'DisPer' || col == 'TaxPer (Total)' || col == 'Prate' || col == 'Mrp' || col == 'Qty') {
            return "0";
          }
          if (col == 'Packing') return "1";
          if (col == 'Exp') return "--/--";
          return "";
        }
        return val;
      }).toList());
    }

    Map<String, List<String>> fieldMappings = {};
    for (var f in standardColumns) {
      fieldMappings[f] = [f];
    }

    Map<String, dynamic> savedBounds = {};
    _fieldBoundaries.forEach((k, v) {
      savedBounds[k] = {'left': v.left, 'right': v.right};
    });

    final layoutConfig = jsonEncode({
      'top': _topBound,
      'bottom': _bottomBound,
      'field_bounds': savedBounds,
    });

    fieldMappings['__PDF_LAYOUT__'] = [layoutConfig];

    String formatName = widget.initialMapping?.name ?? "${widget.currentSupplier.isEmpty ? 'Supplier' : widget.currentSupplier} - PDF";
    if (!formatName.endsWith(" - PDF")) formatName = "$formatName - PDF";

    final mapping = ImportMapping(
      name: formatName,
      fieldMappings: fieldMappings,
    );

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    if (widget.isEditMode && widget.mappingIndex != null) {
      await provider.updateImportMapping(widget.mappingIndex!, mapping);
    } else {
      await provider.addImportMapping(mapping);
    }

    // 1. Close this PDF dialog FIRST so navigation stack is clean
    if (mounted) {
      Navigator.of(context).pop();
    }

    // 2. Trigger the import and mapping on the next frame so it populates the table smoothly
    Future.microtask(() {
      widget.onImportReady(mapping, standardColumns, finalDataRows, false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages.isNotEmpty ? _pages[_currentPageIdx] : null;
    final extractedRows = _extractStructuredRows();
    final sortedFields = _fieldBoundaries.values.toList()..sort((a, b) => a.left.compareTo(b.left));

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.96,
        height: MediaQuery.of(context).size.height * 0.94,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 26),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isEditMode ? "Edit Visual PDF Template" : "Visual PDF Column Mapper",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Supplier: ${widget.currentSupplier.isEmpty ? 'Wholesaler' : widget.currentSupplier}",
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700),
                    ),
                  ],
                ),
                const Spacer(),
                if (_pages.isNotEmpty) ...[
                  if (_pages.length > 1) ...[
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _currentPageIdx > 0 ? () => setState(() => _currentPageIdx--) : null,
                    ),
                    Text("Page ${_currentPageIdx + 1}/${_pages.length}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _currentPageIdx < _pages.length - 1 ? () => setState(() => _currentPageIdx++) : null,
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    icon: const Icon(Icons.zoom_out, size: 20),
                    onPressed: () => setState(() => _canvasScale = (_canvasScale - 0.15).clamp(0.7, 2.0)),
                  ),
                  Text("${(_canvasScale * 100).toInt()}%", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.zoom_in, size: 20),
                    onPressed: () => setState(() => _canvasScale = (_canvasScale + 0.15).clamp(0.7, 2.0)),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: Text(_showFloatingTags ? "Hide Tags" : "Show Tags", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    selected: _showFloatingTags,
                    onSelected: (v) => setState(() => _showFloatingTags = v),
                    avatar: Icon(_showFloatingTags ? Icons.visibility : Icons.visibility_off, size: 14),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _restoreSavedOrAutoLayout();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Reset column boundaries to default auto-detected positions."), duration: Duration(seconds: 1)),
                      );
                    },
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text("Reset Bounds", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade100, foregroundColor: Colors.amber.shade900),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _pickAndParsePdf,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text("Open Sample PDF", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade100, foregroundColor: Colors.blueGrey.shade900),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 12),

            // SINGLE ROW OF HEADINGS
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: allHeadings.map((heading) {
                    bool isMapped = _fieldBoundaries.containsKey(heading);
                    bool isActive = _activeEditingField == heading;
                    bool isDisabled = _isFieldDisabled(heading);
                    Color color = _getFieldColor(heading);

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Opacity(
                        opacity: isDisabled ? 0.35 : 1.0,
                        child: InkWell(
                          onTap: isDisabled ? null : () => _onHeadingClicked(heading),
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isActive ? color : (isMapped ? color.withValues(alpha: 0.18) : (isDisabled ? Colors.grey.shade200 : Colors.white)),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDisabled ? Colors.grey.shade400 : color,
                                width: isActive ? 2.2 : 1.0,
                              ),
                              boxShadow: isActive ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 4, offset: const Offset(0, 2))] : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isMapped) Icon(Icons.check_circle, size: 13, color: isActive ? Colors.white : color),
                                if (isMapped) const SizedBox(width: 4),
                                Text(
                                  heading,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDisabled
                                        ? Colors.grey.shade600
                                        : (isActive ? Colors.white : (isMapped ? color : Colors.black87)),
                                  ),
                                ),
                                if (isMapped) ...[
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: () => _removeHeading(heading),
                                    child: Icon(Icons.cancel, size: 13, color: isActive ? Colors.white70 : Colors.red.shade700),
                                  ),
                                ]
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // WORKSPACE (CANVAS + LIVE PREVIEW)
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _pages.isEmpty
                  ? Center(
                child: ElevatedButton.icon(
                  onPressed: _pickAndParsePdf,
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Select PDF Invoice"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
              )
                  : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT: Canvas
                  Expanded(
                    flex: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: InteractiveViewer(
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(50),
                          minScale: 0.5,
                          maxScale: 3.0,
                          child: _buildPdfVisualCanvas(page!),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // RIGHT: Extracted Preview Table
                  Expanded(
                    flex: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade50,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.table_chart_rounded, size: 18, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                const Text("EXTRACTED PURCHASES PREVIEW", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text("${extractedRows.length} Items Detected", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _fieldBoundaries.isEmpty
                                ? const Center(
                              child: Text(
                                "Click any heading above to map your first column.",
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            )
                                : Builder(
                                    builder: (context) {
                                      final ScrollController horizCtrl = ScrollController();
                                      final ScrollController vertCtrl = ScrollController();
                                      return Scrollbar(
                                        controller: horizCtrl,
                                        thumbVisibility: true,
                                        thickness: 10,
                                        radius: const Radius.circular(5),
                                        child: SingleChildScrollView(
                                          controller: horizCtrl,
                                          scrollDirection: Axis.horizontal,
                                          child: Scrollbar(
                                            controller: vertCtrl,
                                            thumbVisibility: true,
                                            thickness: 8,
                                            child: SingleChildScrollView(
                                              controller: vertCtrl,
                                              scrollDirection: Axis.vertical,
                                              child: DataTable(
                                  headingRowHeight: 32,
                                  dataRowMinHeight: 24,
                                  dataRowMaxHeight: 28,
                                  horizontalMargin: 8,
                                  columnSpacing: 12,
                                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                  columns: sortedFields.map((b) {
                                    return DataColumn(
                                      label: Text(
                                        b.field.toUpperCase(),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: b.color),
                                      ),
                                    );
                                  }).toList(),
                                  rows: extractedRows.map((r) {
                                    return DataRow(
                                      cells: sortedFields.map((b) {
                                        String val = r[b.field] ?? "";
                                        return DataCell(
                                          Text(val.isEmpty ? "-" : val, style: const TextStyle(fontSize: 10)),
                                        );
                                      }).toList(),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Bottom Bar
            Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text(
                  _activeEditingField != null
                      ? "Arranging '$_activeEditingField': Drag its Left & Right lines."
                      : "Drag Green bar (Top) and Red bar (Bottom). Click headings to map columns.",
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _confirmAndSaveTemplate,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text("SAVE TEMPLATE & INWARD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildPdfVisualCanvas(_PdfPageData page) {
    final double canvasW = page.width * _canvasScale;
    final double canvasH = page.height * _canvasScale;

    return Container(
      width: canvasW,
      height: canvasH,
      margin: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ...page.words.map((w) {
            return Positioned(
              left: w.bounds.left * _canvasScale,
              top: w.bounds.top * _canvasScale,
              width: max(w.bounds.width * _canvasScale, 8.0),
              height: max(w.bounds.height * _canvasScale, 10.0),
              child: Text(
                w.text,
                style: TextStyle(
                  fontSize: max(8.0, (w.bounds.height * 0.75) * _canvasScale),
                  color: Colors.black87,
                  fontFamily: 'Roboto',
                ),
                overflow: TextOverflow.visible,
                softWrap: false,
              ),
            );
          }),

          Positioned(
            left: 0, top: 0, right: 0,
            height: _topBound * _canvasScale,
            child: Container(color: Colors.black.withValues(alpha: 0.04)),
          ),
          Positioned(
            left: 0, top: _bottomBound * _canvasScale, right: 0, bottom: 0,
            child: Container(color: Colors.black.withValues(alpha: 0.04)),
          ),

          ..._fieldBoundaries.values.map((boundary) {
            bool isActive = _activeEditingField == boundary.field;
            double leftPx = boundary.left * _canvasScale;
            double rightPx = boundary.right * _canvasScale;
            double widthPx = max(rightPx - leftPx, 8.0);
            double heightPx = (_bottomBound - _topBound) * _canvasScale;

            return Positioned(
              left: leftPx,
              top: _topBound * _canvasScale,
              width: widthPx,
              height: heightPx,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: boundary.color.withValues(alpha: isActive ? 0.22 : 0.10),
                      border: Border.symmetric(
                        horizontal: BorderSide(color: boundary.color.withValues(alpha: 0.3), width: 1),
                      ),
                    ),
                  ),

                  if (_showFloatingTags)
                    Positioned(
                      top: -16,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: boundary.color.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          boundary.field.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                  Positioned(
                    left: -6, top: 0, bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _activeEditingField = boundary.field;
                          double newLeft = boundary.left + (details.delta.dx / _canvasScale);
                          boundary.left = newLeft.clamp(5.0, boundary.right - 10.0);
                        });
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: Container(
                          width: 14,
                          alignment: Alignment.center,
                          child: Container(
                            width: isActive ? 2.5 : 1.5,
                            color: boundary.color,
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    right: -6, top: 0, bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _activeEditingField = boundary.field;
                          double newRight = boundary.right + (details.delta.dx / _canvasScale);
                          boundary.right = newRight.clamp(boundary.left + 10.0, page.width - 5.0);
                        });
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: Container(
                          width: 14,
                          alignment: Alignment.center,
                          child: Container(
                            width: isActive ? 2.5 : 1.5,
                            color: boundary.color,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          Positioned(
            left: 0, right: 0,
            top: (_topBound * _canvasScale) - 10,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                setState(() {
                  double newTop = _topBound + (details.delta.dy / _canvasScale);
                  _topBound = newTop.clamp(20.0, _bottomBound - 20.0);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: Container(
                  height: 20,
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0, right: 0, top: 9,
                        child: Container(height: 2, color: Colors.green.shade700),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text("TABLE START (TOP)", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 0, right: 0,
            top: (_bottomBound * _canvasScale) - 10,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                setState(() {
                  double newBottom = _bottomBound + (details.delta.dy / _canvasScale);
                  _bottomBound = newBottom.clamp(_topBound + 20.0, page.height - 10.0);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: Container(
                  height: 20,
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0, right: 0, top: 9,
                        child: Container(height: 2, color: Colors.red.shade700),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text("TABLE END (BOTTOM)", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}