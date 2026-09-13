import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_formatters.dart';

class GstExportService {
  /// Generates official government GSTR-1 JSON payload map matching GST portal specifications.
  static Future<Map<String, dynamic>> generateGstr1Payload(
    DateTime from,
    DateTime to, {
    PharmacyProvider? provider,
  }) async {
    final String gstin = (provider != null && provider.companyProfile.gstIn.isNotEmpty)
        ? provider.companyProfile.gstIn
        : "32AAAAA0000A1Z5";

    final String financialPeriod = DateFormat('MM20yy').format(from); // e.g., "032026"

    List<SaleInvoice> sales = [];
    if (provider != null) {
      sales = await provider.fetchSalesInDateRange(from, to, loadItems: true, limit: 10000, offset: 0);
    }

    final activeSales = sales.where((s) => !s.isDeleted).toList();

    // Structural sections matching GST portal GSTR-1 JSON schema
    List<Map<String, dynamic>> b2bList = [];
    List<Map<String, dynamic>> b2csList = [];
    List<Map<String, dynamic>> b2clList = [];
    Map<String, Map<String, dynamic>> b2csAggregated = {}; // key: "POS|Rate"
    Map<String, Map<String, dynamic>> hsnAggregated = {}; // key: "HSNCode"
    Map<String, Map<String, dynamic>> b2bGrouped = {}; // key: "GSTIN"

    String firstInvNo = "";
    String lastInvNo = "";
    int totalInvCount = activeSales.length;

    for (var s in activeSales) {
      bool isB2B = (s.customerAcc.toUpperCase() == "CREDIT" && s.mobile.length >= 10);
      String pos = "32"; // Default state code

      // Line item calculation in integer paise
      for (var item in s.items) {
        int totalP = item.totalPaise;
        int gstAmtP = item.gstAmtPaise;
        int itemTaxableP = totalP - gstAmtP;
        if (itemTaxableP < 0) itemTaxableP = 0;

        double rate = item.gstPercent;
        String hsnCode = item.product.hsnCode.isNotEmpty ? item.product.hsnCode : "3004";

        // Aggregate B2C Small by POS & Rate
        if (!isB2B) {
          String b2cKey = "$pos|$rate";
          if (!b2csAggregated.containsKey(b2cKey)) {
            b2csAggregated[b2cKey] = {
              "sply_ty": "INTRA",
              "pos": pos,
              "rt": rate,
              "txval_paise": 0,
              "camt_paise": 0,
              "samt_paise": 0,
              "iamt_paise": 0,
              "csamt_paise": 0,
            };
          }
          b2csAggregated[b2cKey]!["txval_paise"] = (b2csAggregated[b2cKey]!["txval_paise"] as int) + itemTaxableP;
          b2csAggregated[b2cKey]!["camt_paise"] = (b2csAggregated[b2cKey]!["camt_paise"] as int) + item.cgstAmtPaise;
          b2csAggregated[b2cKey]!["samt_paise"] = (b2csAggregated[b2cKey]!["samt_paise"] as int) + item.sgstAmtPaise;
          b2csAggregated[b2cKey]!["iamt_paise"] = (b2csAggregated[b2cKey]!["iamt_paise"] as int) + item.igstAmtPaise;
        }

        // Aggregate HSN Summary
        if (!hsnAggregated.containsKey(hsnCode)) {
          hsnAggregated[hsnCode] = {
            "hsn_sc": hsnCode,
            "desc": item.product.name.isNotEmpty ? item.product.name : "MEDICAMENTS",
            "uqc": "BOX",
            "qty": 0,
            "val_paise": 0,
            "txval_paise": 0,
            "camt_paise": 0,
            "samt_paise": 0,
            "iamt_paise": 0,
            "csamt_paise": 0,
          };
        }
        hsnAggregated[hsnCode]!["qty"] = (hsnAggregated[hsnCode]!["qty"] as int) + item.qty;
        hsnAggregated[hsnCode]!["val_paise"] = (hsnAggregated[hsnCode]!["val_paise"] as int) + totalP;
        hsnAggregated[hsnCode]!["txval_paise"] = (hsnAggregated[hsnCode]!["txval_paise"] as int) + itemTaxableP;
        hsnAggregated[hsnCode]!["camt_paise"] = (hsnAggregated[hsnCode]!["camt_paise"] as int) + item.cgstAmtPaise;
        hsnAggregated[hsnCode]!["samt_paise"] = (hsnAggregated[hsnCode]!["samt_paise"] as int) + item.sgstAmtPaise;
        hsnAggregated[hsnCode]!["iamt_paise"] = (hsnAggregated[hsnCode]!["iamt_paise"] as int) + item.igstAmtPaise;
      }

      // Group B2B Invoices
      if (isB2B) {
        String ctin = "32AAAAA0000A1Z5";
        if (!b2bGrouped.containsKey(ctin)) {
          b2bGrouped[ctin] = {
            "ctin": ctin,
            "inv": <Map<String, dynamic>>[]
          };
        }

        List<Map<String, dynamic>> invItems = s.items.map((item) {
          int totalP = item.totalPaise;
          int gstP = item.gstAmtPaise;
          int taxValP = totalP - gstP;
          if (taxValP < 0) taxValP = 0;

          return {
            "num": 1,
            "itm_det": {
              "rt": item.gstPercent,
              "txval": taxValP.toRupees(),
              "camt": item.cgstAmtPaise.toRupees(),
              "samt": item.sgstAmtPaise.toRupees(),
              "iamt": item.igstAmtPaise.toRupees(),
              "csamt": 0.0
            }
          };
        }).toList();

        (b2bGrouped[ctin]!["inv"] as List).add({
          "inum": s.entryNo,
          "idt": DateFormat('dd-MM-yyyy').format(s.date),
          "val": s.grandTotalPaise.toRupees(),
          "pos": pos,
          "rchrg": "N",
          "inv_type": "R",
          "itms": invItems
        });
      }

      // Track document numbers range
      if (s.entryNo.isNotEmpty) {
        if (firstInvNo.isEmpty) firstInvNo = s.entryNo;
        lastInvNo = s.entryNo;
      }
    }

    // Format B2CS array from aggregated map
    b2csList = b2csAggregated.values.map((v) => {
      "sply_ty": v["sply_ty"],
      "pos": v["pos"],
      "rt": v["rt"],
      "txval": (v["txval_paise"] as int).toRupees(),
      "camt": (v["camt_paise"] as int).toRupees(),
      "samt": (v["samt_paise"] as int).toRupees(),
      "iamt": (v["iamt_paise"] as int).toRupees(),
      "csamt": 0.0
    }).toList();

    // Format HSN summary data
    int hsnIndex = 1;
    List<Map<String, dynamic>> hsnList = hsnAggregated.values.map((v) => {
      "num": hsnIndex++,
      "hsn_sc": v["hsn_sc"],
      "desc": v["desc"],
      "uqc": v["uqc"],
      "qty": v["qty"],
      "val": (v["val_paise"] as int).toRupees(),
      "txval": (v["txval_paise"] as int).toRupees(),
      "camt": (v["camt_paise"] as int).toRupees(),
      "samt": (v["samt_paise"] as int).toRupees(),
      "iamt": (v["iamt_paise"] as int).toRupees(),
      "csamt": 0.0
    }).toList();

    b2bList = b2bGrouped.values.toList();

    int grossTurnoverPaise = activeSales.fold(0, (sum, s) => sum + s.grandTotalPaise);

    return {
      "gstin": gstin,
      "fp": financialPeriod,
      "gt": grossTurnoverPaise.toRupees(),
      "cur_gt": grossTurnoverPaise.toRupees(),
      "version": "GST_1.0",
      "b2b": b2bList,
      "b2cs": b2csList,
      "b2cl": b2clList,
      "hsn": {
        "data": hsnList
      },
      "doc_issue": {
        "doc_det": [
          {
            "doc_num": 1,
            "doc_typ": "Invoices for outward supply",
            "docs": [
              {
                "num": 1,
                "from": firstInvNo.isNotEmpty ? firstInvNo : "INV-0001",
                "to": lastInvNo.isNotEmpty ? lastInvNo : "INV-0001",
                "totcnt": totalInvCount,
                "canc": 0,
                "net_issue": totalInvCount
              }
            ]
          }
        ]
      }
    };
  }

  /// Exports GSTR-1 JSON file directly to the specified destination path.
  static Future<File> exportGstr1JsonFile(
    DateTime from,
    DateTime to,
    String destinationPath, {
    PharmacyProvider? provider,
  }) async {
    final payload = await generateGstr1Payload(from, to, provider: provider);
    final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
    final file = File(destinationPath);
    await file.writeAsString(jsonString);
    return file;
  }
}
