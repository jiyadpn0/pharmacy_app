class HsnMasterItem {
  final String hsnCode;
  final String description;
  final double gstPercent;

  HsnMasterItem({
    required this.hsnCode,
    required this.description,
    required this.gstPercent,
  });

  /// Standard HSN codes for pharmaceuticals
  static final List<HsnMasterItem> defaultHsnList = [
    HsnMasterItem(hsnCode: '3004', description: 'Medicaments (Aylurvedic, Homeopathic, Allopathic)', gstPercent: 12.0),
    HsnMasterItem(hsnCode: '3002', description: 'Vaccines, Toxins & Blood Fractions', gstPercent: 5.0),
    HsnMasterItem(hsnCode: '9018', description: 'Surgical & Medical Instruments', gstPercent: 12.0),
    HsnMasterItem(hsnCode: '3304', description: 'Cosmetics & Skin Care Preparations', gstPercent: 18.0),
  ];

  static double getGstPercentForHsn(String code) {
    final match = defaultHsnList.firstWhere(
      (item) => item.hsnCode == code.trim(),
      orElse: () => HsnMasterItem(hsnCode: code, description: 'General', gstPercent: 12.0),
    );
    return match.gstPercent;
  }
}
