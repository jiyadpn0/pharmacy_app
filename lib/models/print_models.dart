enum DotMatrixPaperSize {
  inch_8x11,     // Standard Full Page (8.5 x 11 inches)
  inch_8x6,      // Half Page Continuous
  inch_6x6,      // Small Square Continuous
  inch_4x6,      // Docket / Challan Roll or Sheet
  custom         // Custom user-defined rows/cols
}

class PrintProfile {
  final String id;
  final String modelName;
  final int maxColumns;          // e.g., 80 columns or 136 columns for wide carriage
  final DotMatrixPaperSize paperSize;
  final int customLinesPerPage;  // e.g., 66 lines for 11 inch at 6 LPI
  final bool useEscP;            // ESC/P command support vs. raw plain text

  PrintProfile({
    required this.id,
    required this.modelName,
    required this.maxColumns,
    required this.paperSize,
    this.customLinesPerPage = 66,
    this.useEscP = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'modelName': modelName,
    'maxColumns': maxColumns,
    'paperSize': paperSize.index,
    'customLinesPerPage': customLinesPerPage,
    'useEscP': useEscP ? 1 : 0,
  };

  factory PrintProfile.fromMap(Map<String, dynamic> map) => PrintProfile(
    id: map['id'],
    modelName: map['modelName'],
    maxColumns: map['maxColumns'],
    paperSize: DotMatrixPaperSize.values[map['paperSize']],
    customLinesPerPage: map['customLinesPerPage'],
    useEscP: map['useEscP'] == 1,
  );
}
