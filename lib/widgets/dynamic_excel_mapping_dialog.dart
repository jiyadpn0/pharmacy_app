import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../providers/pharmacy_provider.dart';

class DynamicExcelMappingDialog extends StatefulWidget {
  final List<String> excelHeaders;
  final String filePath;
  final PharmacyProvider provider;
  final Function(ImportMapping) onImportComplete;
  final ImportMapping? initialMapping;
  final int? mappingIndex;
  final Function(ImportMapping?)? closeWindow;

  const DynamicExcelMappingDialog({
    super.key,
    required this.excelHeaders,
    required this.filePath,
    required this.provider,
    required this.onImportComplete,
    this.initialMapping,
    this.mappingIndex,
    this.closeWindow,
  });

  @override
  State<DynamicExcelMappingDialog> createState() => _DynamicExcelMappingDialogState();
}

class _DynamicExcelMappingDialogState extends State<DynamicExcelMappingDialog> {
  final TextEditingController _wholesalerNameCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _wholesalerFocusNode = FocusNode();
  List<String> _currentHeaders = [];
  bool _isLoading = false;

  final List<String> appFields = [
    'Product Code', 'Product', 'Batch', 'Exp', 'HSN', 'Packing', 'Qty', 'Fqty',
    'Prate', 'Mrp', 'DisPer', 'DisAmt', 'TaxPer (Total)', 'CGST', 'SGST'
  ];

  final Map<String, String?> selectedMappings = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  ImportMapping? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    _currentHeaders = List.from(widget.excelHeaders);

    if (widget.initialMapping != null) {
      String tempName = widget.initialMapping!.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', '');
      if (tempName == "NEW_SUPPLIER_FORMAT") {
        _wholesalerNameCtrl.text = "";
      } else {
        _wholesalerNameCtrl.text = tempName;
      }
    }

    _initializeFields(isFirstTime: true);
  }

  void _initializeFields({bool isFirstTime = false}) {
    for (var field in appFields) {
      if (isFirstTime) {
        selectedMappings[field] = null;
      }

      if (!_controllers.containsKey(field)) {
        _controllers[field] = TextEditingController();
        _focusNodes[field] = FocusNode();

        _focusNodes[field]!.addListener(() {
          if (mounted && !_focusNodes[field]!.hasFocus) {
            final controller = _controllers[field]!;
            final currentOpts = ["-- Ignore --", ..._currentHeaders];

            if (_currentHeaders.isNotEmpty && controller.text.isNotEmpty && !currentOpts.contains(controller.text)) {
              setState(() {
                controller.clear();
                selectedMappings[field] = null;
              });
            }
          }
        });
      }

      if (isFirstTime && widget.initialMapping != null) {
        final savedKeywords = widget.initialMapping!.fieldMappings[field];
        if (savedKeywords != null && savedKeywords.isNotEmpty) {
          String? matchedHeader;
          if (_currentHeaders.isNotEmpty) {
            for (var h in _currentHeaders) {
              String cleanH = h.trim().toLowerCase();
              if (field == 'Mrp' && (cleanH.contains('vaton') || cleanH.contains('vat_on') || cleanH.contains('tax_on') || cleanH.contains('taxonsch'))) {
                continue;
              }
              if (savedKeywords.any((m) => m.toLowerCase() == cleanH)) {
                matchedHeader = h;
                break;
              }
            }
          }

          String valToShow = matchedHeader ?? savedKeywords.first;
          selectedMappings[field] = valToShow;
          _controllers[field]!.text = valToShow;
        }
      }

      // Auto-detect from default keywords if field is still unmapped and headers exist
      if (_currentHeaders.isNotEmpty && (selectedMappings[field] == null || selectedMappings[field]!.isEmpty || _controllers[field]!.text.isEmpty)) {
        final defaultKw = ImportMapping.defaultMapping().fieldMappings[field];
        if (defaultKw != null) {
          String? matchedHeader;
          for (var h in _currentHeaders) {
            String cleanH = h.trim().toLowerCase();
            if (field == 'Mrp' && (cleanH.contains('vaton') || cleanH.contains('vat_on') || cleanH.contains('tax_on') || cleanH.contains('taxonsch'))) {
              continue;
            }
            String normH = cleanH.replaceAll(RegExp(r'[^a-z0-9]'), '');
            for (var k in defaultKw) {
              String cleanK = k.trim().toLowerCase();
              String normK = cleanK.replaceAll(RegExp(r'[^a-z0-9]'), '');
              if (cleanH == cleanK || normH == normK) {
                matchedHeader = h;
                break;
              }
            }
            if (matchedHeader != null) break;
          }

          if (matchedHeader != null) {
            selectedMappings[field] = matchedHeader;
            _controllers[field]!.text = matchedHeader;
          }
        }
      }
    }
  }

  Future<void> _fetchHeadersFromFile() async {
    try {
      bool isPdf = widget.filePath.toLowerCase().contains("pdf");
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: isPdf ? ['pdf'] : ['xlsx', 'xls', 'csv'],
      );

      if (result == null || result.files.single.path == null) return;

      setState(() => _isLoading = true);
      String path = result.files.single.path!;
      List<String> extractedHeaders = [];

      if (isPdf) {
        final bytes = File(path).readAsBytesSync();
        PdfDocument document = PdfDocument(inputBytes: bytes);
        PdfTextExtractor extractor = PdfTextExtractor(document);

        List<TextLine> textLines = extractor.extractTextLines();
        document.dispose();

        if (textLines.isNotEmpty) {
          List<List<TextWord>> physicalRows = [];
          for (var line in textLines) {
            for (var word in line.wordCollection) {
              if (word.text.trim().isEmpty) continue;
              bool added = false;
              for (var row in physicalRows) {
                if ((row.first.bounds.top - word.bounds.top).abs() < 8.0) {
                  row.add(word);
                  added = true;
                  break;
                }
              }
              if (!added) physicalRows.add([word]);
            }
          }

          physicalRows.sort((a, b) => a.first.bounds.top.compareTo(b.first.bounds.top));

          int headerIndex = -1;
          for (int i = 0; i < physicalRows.length; i++) {
            String text = physicalRows[i].map((w) => w.text).join(' ').toLowerCase();
            if (text.contains('description') || text.contains('product') || (text.contains('batch') && text.contains('qty'))) {
              headerIndex = i;
              break;
            }
          }

          if (headerIndex != -1) {
            var headerWords = physicalRows[headerIndex];
            headerWords.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));

            List<Rect> headerBounds = [];

            String currentCol = headerWords.first.text;
            double currentLeft = headerWords.first.bounds.left;
            double currentRight = headerWords.first.bounds.right;

            for (int i = 1; i < headerWords.length; i++) {
              TextWord prevWord = headerWords[i-1];
              TextWord currWord = headerWords[i];

              double gap = currWord.bounds.left - currentRight;
              double charWidth = prevWord.bounds.width / (prevWord.text.isNotEmpty ? prevWord.text.length : 1);

              if (gap > charWidth * 0.9 || currWord.text == '|' || prevWord.text == '|') {
                String cleanCol = currentCol.replaceAll('|', '').trim();
                if (cleanCol.isNotEmpty) {
                  extractedHeaders.add(cleanCol);
                  headerBounds.add(Rect.fromLTRB(currentLeft, 0, currentRight, 0));
                }
                currentCol = currWord.text;
                currentLeft = currWord.bounds.left;
                currentRight = currWord.bounds.right;
              } else {
                currentCol += " ${currWord.text}";
                currentRight = currWord.bounds.right;
              }
            }
            String finalCol = currentCol.replaceAll('|', '').trim();
            if (finalCol.isNotEmpty) {
              extractedHeaders.add(finalCol);
              headerBounds.add(Rect.fromLTRB(currentLeft, 0, currentRight, 0));
            }

            List<double> walls = [];
            walls.add(-9999.0);
            for (int i = 0; i < headerBounds.length - 1; i++) {
              walls.add((headerBounds[i].right + headerBounds[i+1].left) / 2.0);
            }
            walls.add(99999.0);

            for (int r = headerIndex + 1; r < headerIndex + 3 && r < physicalRows.length; r++) {
              var rowWords = physicalRows[r];
              bool isData = rowWords.any((w) => RegExp(r'\d{2}[-/]\d{2,4}').hasMatch(w.text) || (RegExp(r'^\d+$').hasMatch(w.text) && rowWords.length > 5));
              if (isData) break;

              for (var word in rowWords) {
                if (word.text == '|') continue;
                double wordCenter = word.bounds.left + (word.bounds.width / 2.0);
                for (int c = 0; c < extractedHeaders.length; c++) {
                  if (wordCenter >= walls[c] && wordCenter < walls[c+1]) {
                    extractedHeaders[c] = "${extractedHeaders[c]} ${word.text.trim()}".trim();
                    break;
                  }
                }
              }
            }
          }
        }
      } else {
        final p = widget.provider;
        final data = await p.getExcelDataForPreview(path);
        if (data['success'] == true) {
          extractedHeaders = List<String>.from(data['header'] ?? []);
        }
      }

      if (extractedHeaders.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _currentHeaders = extractedHeaders;
          _initializeFields(isFirstTime: false);
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Found ${extractedHeaders.length} columns perfectly mapped!"), backgroundColor: Colors.green));
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not detect columns."), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  void dispose() {
    _wholesalerNameCtrl.dispose();
    _scrollController.dispose();
    _wholesalerFocusNode.dispose();
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    for (var node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _copyFormatFrom(ImportMapping template) {
    setState(() {
      for (var field in appFields) {
        final savedKeywords = template.fieldMappings[field];
        if (savedKeywords != null && savedKeywords.isNotEmpty) {
          String? matchedHeader;
          if (_currentHeaders.isNotEmpty) {
            for (var h in _currentHeaders) {
              if (savedKeywords.any((k) => k.toLowerCase() == h.toLowerCase())) {
                matchedHeader = h;
                break;
              }
            }
          }

          String valToCopy = matchedHeader ?? savedKeywords.first;

          selectedMappings[field] = valToCopy;
          _controllers[field]!.text = valToCopy;
        } else {
          selectedMappings[field] = null;
          _controllers[field]!.clear();
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Copied settings from ${template.name}"), backgroundColor: Colors.blue, duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> dropdownItems = ["-- Ignore --", ..._currentHeaders];
    bool isPdfContext = widget.filePath.toLowerCase().contains("pdf");
    bool isVisualPdf = widget.filePath == "pdf_visual";
    Color highlightColor = isPdfContext ? Colors.red.shade700 : Colors.blue.shade800;
    Color bgColor = isPdfContext ? Colors.red.shade50 : Colors.blue.shade50;
    String typeSuffix = isPdfContext ? " - PDF" : " - EXCEL";

    List<ImportMapping> availableCopyFormats = widget.provider.importMappings.where((m) {
      bool isPdfFormat = m.name.toUpperCase().endsWith('- PDF');
      return isPdfContext ? isPdfFormat : !isPdfFormat;
    }).toList();

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          if (widget.closeWindow != null) {
            widget.closeWindow!(null);
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 600,
          height: 600,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                Text(isPdfContext ? "Map PDF Invoice Columns" : "Map Uploaded Excel Columns",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 15),

                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _wholesalerNameCtrl.text),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return widget.provider.suppliers;
                    }
                    return widget.provider.suppliers.where((String option) {
                      return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  onSelected: (String selection) {
                    _wholesalerNameCtrl.text = selection.toUpperCase();
                    if (appFields.isNotEmpty) {
                      _focusNodes[appFields.first]?.requestFocus();
                    }
                  },
                  fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                    if (controller.text.isEmpty && _wholesalerNameCtrl.text.isNotEmpty) {
                      controller.text = _wholesalerNameCtrl.text;
                    }

                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onEditingComplete: onEditingComplete,
                      decoration: InputDecoration(
                        labelText: "Save this Format As (e.g. SAKTHI WHOLESALE)",
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: highlightColor, width: 2)),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),

                if (isVisualPdf)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("VISUAL MAPPING CAPTURED", style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                              Text("Your dragged columns are locked and auto-filled. Name your format to save.", style: TextStyle(color: Colors.green.shade700, fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  InkWell(
                    onTap: _isLoading ? null : _fetchHeadersFromFile,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: highlightColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(isPdfContext ? Icons.picture_as_pdf : Icons.table_chart, color: highlightColor, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isPdfContext ? "UPLOAD PDF TO FETCH HEADINGS" : "UPLOAD EXCEL/CSV TO FETCH HEADINGS",
                                  style: TextStyle(color: highlightColor, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                Text(
                                  isPdfContext ? "Automatically detects columns from your PDF file" : "Load column names from an existing Excel/CSV file",
                                  style: TextStyle(color: highlightColor.withValues(alpha: 0.7), fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          if (_isLoading)
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: highlightColor))
                          else
                            Icon(Icons.upload_file, color: highlightColor, size: 18),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 10),

                if (availableCopyFormats.isNotEmpty && !isVisualPdf)
                  DropdownButtonFormField<ImportMapping>(
                    decoration: InputDecoration(
                      labelText: isPdfContext
                          ? "Copy settings from an existing PDF format (Optional)"
                          : "Copy settings from an existing Excel format (Optional)",
                      border: const OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: bgColor,
                      prefixIcon: Icon(Icons.copy, size: 18, color: highlightColor),
                    ),
                    initialValue: _selectedTemplate,
                    hint: Text(
                        isPdfContext ? "Select a saved PDF format to copy..." : "Select a saved Excel format to copy...",
                        style: const TextStyle(fontSize: 12)
                    ),
                    items: availableCopyFormats.map((m) {
                      return DropdownMenuItem<ImportMapping>(
                        value: m,
                        child: Text(m.name.replaceAll(' - PDF', '').replaceAll(' - EXCEL', ''), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                    onChanged: (ImportMapping? val) {
                      if (val != null) {
                        setState(() => _selectedTemplate = val);
                        _copyFormatFrom(val);
                      }
                    },
                  ),

                const SizedBox(height: 15),
                Text(
                  isVisualPdf
                      ? "Visually mapped fields are locked. You can manually map the remaining fields if needed."
                      : "Match your application's fields to the columns found in your uploaded file.",
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
                ),
                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  color: Colors.blueGrey.shade100,
                  child: const Row(
                    children: [
                      Expanded(flex: 1, child: Text("App Field", style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text("Search Excel/CSV Column", style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),

                ...List.generate(appFields.length, (index) {
                  String field = appFields[index];
                  bool isDisabled = false;
                  String hintMessage = "Search column name...";

                  bool visuallyMapped = isVisualPdf && widget.initialMapping != null &&
                      widget.initialMapping!.fieldMappings.containsKey('__visual_col_$field');

                  if (visuallyMapped) {
                    isDisabled = true;
                    hintMessage = "Mapped Visually";
                  } else if (field == 'CGST' || field == 'SGST') {
                    if (selectedMappings['TaxPer (Total)'] != null) {
                      isDisabled = true;
                      hintMessage = "Locked (Using Total Tax)";
                    }
                  } else if (field == 'TaxPer (Total)') {
                    if (selectedMappings['CGST'] != null || selectedMappings['SGST'] != null) {
                      isDisabled = true;
                      hintMessage = "Locked (Using CGST/SGST)";
                    }
                  }

                  Widget rowWidget = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                      color: isDisabled ? Colors.grey.shade100 : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 1, child: Text(field, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDisabled ? Colors.grey : Colors.black))),
                        Expanded(
                          flex: 2,
                          child: Autocomplete<String>(
                            key: ValueKey("auto_${field}_${_currentHeaders.length}"),
                            focusNode: _focusNodes[field],
                            textEditingController: _controllers[field],
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (isDisabled) return const Iterable<String>.empty();
                              if (textEditingValue.text.isEmpty) return dropdownItems;

                              if (dropdownItems.contains(textEditingValue.text)) {
                                return const Iterable<String>.empty();
                              }

                              return dropdownItems.where((String option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                            },
                            onSelected: (String selection) {
                              if (isDisabled) return;
                              setState(() {
                                selectedMappings[field] = selection == "-- Ignore --" ? null : selection;
                                _controllers[field]!.text = selection;
                              });
                              Future.delayed(const Duration(milliseconds: 50), () {
                                if (mounted) {
                                  int curIdx = appFields.indexOf(field);
                                  if (curIdx != -1 && curIdx < appFields.length - 1) {
                                    String nextFieldKey = appFields[curIdx + 1];
                                    _focusNodes[nextFieldKey]?.requestFocus();
                                  } else {
                                    _focusNodes[field]?.unfocus();
                                  }
                                }
                              });
                            },
                            fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                enabled: !isDisabled,
                                onSubmitted: (val) {
                                  if (isDisabled) return;
                                  onEditingComplete();
                                  Future.delayed(const Duration(milliseconds: 100), () {
                                    if (mounted && focusNode.hasFocus) {
                                      int curIdx = appFields.indexOf(field);
                                      if (curIdx != -1 && curIdx < appFields.length - 1) {
                                        _focusNodes[appFields[curIdx + 1]]?.requestFocus();
                                      }
                                    }
                                  });
                                },
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDisabled ? (visuallyMapped ? Colors.green.shade800 : Colors.grey) : Colors.black),
                                decoration: InputDecoration(
                                  hintText: hintMessage,
                                  hintStyle: TextStyle(color: isDisabled ? (visuallyMapped ? Colors.green.shade600 : Colors.red.shade300) : Colors.grey),
                                  suffixIcon: Icon(isDisabled ? (visuallyMapped ? Icons.verified : Icons.lock) : Icons.search, size: 18, color: isDisabled ? (visuallyMapped ? Colors.green.shade600 : Colors.red.shade300) : Colors.blueGrey),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  filled: isDisabled,
                                  fillColor: visuallyMapped ? Colors.green.shade50 : Colors.grey.shade200,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                ),
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(4),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 250, maxWidth: 350),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero, shrinkWrap: true, itemCount: options.length,
                                      itemBuilder: (BuildContext context, int index) {
                                        final String option = options.elementAt(index);
                                        return Builder(
                                            builder: (BuildContext context) {
                                              final bool highlight = AutocompleteHighlightedOption.of(context) == index;
                                              if (highlight) {
                                                WidgetsBinding.instance.addPostFrameCallback((_) => Scrollable.ensureVisible(context, alignment: 0.5));
                                              }
                                              return InkWell(
                                                onTap: () => onSelected(option),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(color: highlight ? Colors.blue.shade50 : Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                                                  child: Text(option, style: TextStyle(fontSize: 13, fontWeight: highlight ? FontWeight.bold : FontWeight.normal, color: highlight ? Colors.blue.shade900 : Colors.black87)),
                                                ),
                                              );
                                            }
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );

                  if (field == 'TaxPer (Total)') {
                    return Column(
                      key: ValueKey("col_$field"),
                      children: [
                        rowWidget,
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text("— OR —", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade400, letterSpacing: 1.5)),
                        ),
                      ],
                    );
                  }
                  return rowWidget;
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    if (widget.closeWindow != null) {
                      widget.closeWindow!(null);
                    } else if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("CANCEL", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 15),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () {
                    if (_wholesalerNameCtrl.text.trim().isEmpty) {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      }
                      _wholesalerFocusNode.requestFocus();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please enter a Wholesaler Name at the top."),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }

                    final fieldMappings = <String, List<String>>{};
                    selectedMappings.forEach((appField, excelHeader) {
                      if (excelHeader != null && excelHeader != "-- Ignore --") {
                        fieldMappings[appField] = [excelHeader.trim().toLowerCase()];
                      }
                    });

                    if (widget.initialMapping != null && isVisualPdf) {
                      widget.initialMapping!.fieldMappings.forEach((k, v) {
                        if (k.startsWith('__')) {
                          fieldMappings[k] = v;
                        }
                      });
                    }

                    String cleanWholesaler = _wholesalerNameCtrl.text.trim().toUpperCase();
                    cleanWholesaler = cleanWholesaler.replaceAll(' - PDF', '').replaceAll(' - EXCEL', '').trim();
                    widget.provider.addSupplier(cleanWholesaler);

                    String finalName = "$cleanWholesaler$typeSuffix";

                    final newMapping = ImportMapping(
                        name: finalName,
                        fieldMappings: fieldMappings
                    );

                    if (widget.mappingIndex != null) {
                      widget.provider.updateImportMapping(widget.mappingIndex!, newMapping);
                    } else {
                      widget.provider.addImportMapping(newMapping);
                    }
                    widget.onImportComplete(newMapping);

                    if (widget.closeWindow != null) {
                      widget.closeWindow!(newMapping);
                    } else if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("SAVE"),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}

