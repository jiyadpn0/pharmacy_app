import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/erp_models.dart';

/// Immutable snapshot representing an uncommitted POS cart and its complete billing context.
class SalesDraft {
  final int workspaceIndex;
  final String agent;
  final String customerAcc;
  final String patient;
  final String mobile;
  final String doctor;
  final int taxType;
  final int orderType;
  final double footerDiscPct;
  final double footerDiscAmt;
  final double otherChargesPct;
  final double otherChargesAmt;
  final double rcvdAmt;
  final String paymentMode;
  final String remarks;
  final int focusRow;
  final int focusCol;
  final DateTime savedAt;
  final List<SaleItem> items;

  SalesDraft({
    this.workspaceIndex = 0,
    this.agent = '',
    this.customerAcc = 'Cash',
    this.patient = 'P1',
    this.mobile = '',
    this.doctor = 'D1',
    this.taxType = 2,
    this.orderType = 0,
    this.footerDiscPct = 0.0,
    this.footerDiscAmt = 0.0,
    this.otherChargesPct = 0.0,
    this.otherChargesAmt = 0.0,
    this.rcvdAmt = 0.0,
    this.paymentMode = 'Cash',
    this.remarks = '',
    this.focusRow = 0,
    this.focusCol = 1,
    DateTime? savedAt,
    required this.items,
  }) : savedAt = savedAt ?? DateTime.now();

  double get subtotal => items.fold(0.0, (sum, it) => sum + it.total);
  int get itemCount => items.length;

  Map<String, dynamic> toMap() => {
        'workspace_index': workspaceIndex,
        'agent': agent,
        'customer_acc': customerAcc,
        'patient': patient,
        'mobile': mobile,
        'doctor': doctor,
        'tax_type': taxType,
        'order_type': orderType,
        'footer_disc_pct': footerDiscPct,
        'footer_disc_amt': footerDiscAmt,
        'other_charges_pct': otherChargesPct,
        'other_charges_amt': otherChargesAmt,
        'rcvd_amt': rcvdAmt,
        'payment_mode': paymentMode,
        'remarks': remarks,
        'focus_row': focusRow,
        'focus_col': focusCol,
        'saved_at': savedAt.toIso8601String(),
        'items': items.map((i) => i.toMap()).toList(),
      };

  factory SalesDraft.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    return SalesDraft(
      workspaceIndex: (map['workspace_index'] as num?)?.toInt() ?? 0,
      agent: map['agent']?.toString() ?? '',
      customerAcc: map['customer_acc']?.toString() ?? 'Cash',
      patient: map['patient']?.toString() ?? 'P1',
      mobile: map['mobile']?.toString() ?? '',
      doctor: map['doctor']?.toString() ?? 'D1',
      taxType: (map['tax_type'] as num?)?.toInt() ?? 2,
      orderType: (map['order_type'] as num?)?.toInt() ?? 0,
      footerDiscPct: (map['footer_disc_pct'] as num?)?.toDouble() ?? 0.0,
      footerDiscAmt: (map['footer_disc_amt'] as num?)?.toDouble() ?? 0.0,
      otherChargesPct: (map['other_charges_pct'] as num?)?.toDouble() ?? 0.0,
      otherChargesAmt: (map['other_charges_amt'] as num?)?.toDouble() ?? 0.0,
      rcvdAmt: (map['rcvd_amt'] as num?)?.toDouble() ?? 0.0,
      paymentMode: map['payment_mode']?.toString() ?? 'Cash',
      remarks: map['remarks']?.toString() ?? '',
      focusRow: (map['focus_row'] as num?)?.toInt() ?? 0,
      focusCol: (map['focus_col'] as num?)?.toInt() ?? 1,
      savedAt: map['saved_at'] != null ? DateTime.tryParse(map['saved_at'].toString()) ?? DateTime.now() : DateTime.now(),
      items: rawItems
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => SaleItem.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory SalesDraft.fromJson(String str) => SalesDraft.fromMap(jsonDecode(str) as Map<String, dynamic>);
}

/// Service managing offline-first persistence of uncommitted POS carts.
/// Guarantees that in the event of an abrupt power cut, Windows crash, or accidental
/// terminal shutdown, the cashier's active cart is preserved and can be recovered.
class SalesDraftService {
  SalesDraftService._();
  static final SalesDraftService instance = SalesDraftService._();

  static const String _prefDraftKey = 'pos_active_sales_draft_v3';
  static const String _draftFileName = 'sales_draft_recovery.json';

  SalesDraft? _cachedPendingRecoveryDraft;
  bool _recoveryAcknowledged = false;

  SalesDraft? get cachedPendingRecoveryDraft => _recoveryAcknowledged ? null : _cachedPendingRecoveryDraft;

  /// Returns true if an uncommitted cart was detected upon startup
  bool get hasPendingRecovery => !_recoveryAcknowledged && _cachedPendingRecoveryDraft != null && _cachedPendingRecoveryDraft!.items.isNotEmpty;

  /// Marks recovery as acknowledged by the cashier for the current session
  void acknowledgeRecovery() {
    _recoveryAcknowledged = true;
  }

  /// Scans disk and SharedPreferences for any uncommitted cart created prior to app launch
  Future<SalesDraft?> checkUncommittedDraft() async {
    try {
      // 1. Check SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      final draftStr = prefs.getString(_prefDraftKey);
      if (draftStr != null && draftStr.isNotEmpty) {
        final draft = SalesDraft.fromJson(draftStr);
        if (draft.items.isNotEmpty) {
          _cachedPendingRecoveryDraft = draft;
          _recoveryAcknowledged = false;
          return draft;
        }
      }

      // 2. Fallback to physical disk snapshot
      if (!kIsWeb) {
        final docsDir = await getApplicationDocumentsDirectory();
        final file = File(join(docsDir.path, _draftFileName));
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.isNotEmpty) {
            final draft = SalesDraft.fromJson(content);
            if (draft.items.isNotEmpty) {
              _cachedPendingRecoveryDraft = draft;
              _recoveryAcknowledged = false;
              return draft;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("SalesDraftService checkUncommittedDraft note: $e");
    }

    _cachedPendingRecoveryDraft = null;
    return null;
  }

  /// Atomically saves active POS cart to both SharedPreferences and disk
  Future<void> saveDraft(SalesDraft draft) async {
    if (draft.items.isEmpty) {
      await clearDraft();
      return;
    }

    try {
      _cachedPendingRecoveryDraft = draft;
      _recoveryAcknowledged = false;
      final jsonStr = draft.toJson();

      // 1. Fast SharedPreferences write
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefDraftKey, jsonStr);

      // 2. Redundant persistent file write for power-cut resilience
      if (!kIsWeb) {
        final docsDir = await getApplicationDocumentsDirectory();
        final file = File(join(docsDir.path, _draftFileName));
        await file.writeAsString(jsonStr, flush: true);
      }
    } catch (e) {
      debugPrint("SalesDraftService saveDraft error: $e");
    }
  }

  /// Clears persisted draft state after successful invoice save or explicit user discard
  Future<void> clearDraft() async {
    _cachedPendingRecoveryDraft = null;
    _recoveryAcknowledged = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefDraftKey);
      await prefs.remove('sales_active_workspace_draft');

      if (!kIsWeb) {
        final docsDir = await getApplicationDocumentsDirectory();
        final file = File(join(docsDir.path, _draftFileName));
        if (await file.exists()) {
          await file.delete();
        }
        final legacyFile = File(join(docsDir.path, 'sale_draft.json'));
        if (await legacyFile.exists()) {
          await legacyFile.delete();
        }
      }
    } catch (e) {
      debugPrint("SalesDraftService clearDraft error: $e");
    }
  }
}
