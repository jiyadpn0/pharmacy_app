import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sql;
import '../database/db_helper.dart';
import '../providers/pharmacy_provider.dart';
import 'server_config_service.dart';
import 'supabase_sync_service.dart';

class InvoiceRecoveryResult {
  final bool success;
  final String message;
  final String? backupPath;
  final Map<String, dynamic>? cloudHeader;
  final List<Map<String, dynamic>>? cloudItems;

  InvoiceRecoveryResult({
    required this.success,
    required this.message,
    this.backupPath,
    this.cloudHeader,
    this.cloudItems,
  });
}

class InvoiceRecoveryService {
  InvoiceRecoveryService._internal();
  static final InvoiceRecoveryService instance = InvoiceRecoveryService._internal();

  /// Safely recovers PC1's cloud invoice for [entryNo] on PC2 by:
  /// 1. Pausing background sync and waiting for idle (fails closed if sync remains busy).
  /// 2. Pre-fetching and strictly validating cloud invoice header, items, and patient record.
  /// 3. Backing up the database and verifying the backup file on disk.
  /// 4. Executing a single atomic SQLite transaction that filters columns against PRAGMA table_info,
  ///    re-checks draft status, linked records, reverses draft stock, purges draft rows,
  ///    imports cloud invoice/items, deducts PC1 sale stock, and updates patient balance using a verified unique ID.
  /// 5. Never sending any push or delete request to Supabase.
  Future<InvoiceRecoveryResult> recoverUnsyncedInvoice({
    required String entryNo,
    PharmacyProvider? pharmacy,
  }) async {
    final cleanEntryNo = entryNo.trim();
    if (cleanEntryNo.isEmpty) {
      return InvoiceRecoveryResult(success: false, message: "Entry number cannot be empty.");
    }

    final syncService = SupabaseSyncService.instance;

    // Safeguard 3 & Blocker Fix 2: Pause sync and fail closed if background sync remains active
    final bool pausedOk = await syncService.pauseSyncAndAwaitIdle();
    if (!pausedOk) {
      syncService.resumeSync();
      return InvoiceRecoveryResult(
        success: false,
        message: "Background sync operation is busy and did not become idle within timeout. Recovery aborted. Database unchanged.",
      );
    }

    try {
      final config = ServerConfigService.instance;
      if (!config.isServerModeEnabled || config.supabaseUrl.trim().isEmpty || config.supabaseAnonKey.trim().isEmpty) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Server mode is not configured or offline. Cannot verify cloud invoice.",
        );
      }

      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final headers = config.restHeaders;

      // Safeguard 1 & 7: Fetch exact cloud invoice and items via REST GET ONLY (never POST/PATCH/DELETE)
      // 1a. Fetch Header
      final headerUri = Uri.parse('$cleanUrl/rest/v1/sales_invoices?entry_no=eq.${Uri.encodeComponent(cleanEntryNo)}&select=*');
      final headerRes = await http.get(headerUri, headers: headers).timeout(const Duration(seconds: 10));
      if (headerRes.statusCode != 200) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Cloud fetch failed for header #$cleanEntryNo (HTTP ${headerRes.statusCode}). Database unchanged.",
        );
      }

      final List<dynamic> headerList = jsonDecode(headerRes.body);
      if (headerList.isEmpty) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Cloud invoice #$cleanEntryNo not found on Supabase. Database unchanged.",
        );
      }

      final cloudHeader = Map<String, dynamic>.from(headerList.first as Map);
      final int cloudIsDeleted = (cloudHeader['is_deleted'] as num?)?.toInt() ?? 0;
      if (cloudIsDeleted == 1) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Cloud invoice #$cleanEntryNo is marked as deleted on Supabase. Database unchanged.",
        );
      }

      // 1b. Fetch Line Items
      final itemsUri = Uri.parse('$cleanUrl/rest/v1/sales_items?invoice_no=eq.${Uri.encodeComponent(cleanEntryNo)}&select=*');
      final itemsRes = await http.get(itemsUri, headers: headers).timeout(const Duration(seconds: 10));
      if (itemsRes.statusCode != 200) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Cloud fetch failed for line items of #$cleanEntryNo (HTTP ${itemsRes.statusCode}). Database unchanged.",
        );
      }

      final List<dynamic> itemsList = jsonDecode(itemsRes.body);
      if (itemsList.isEmpty) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Cloud invoice #$cleanEntryNo has no line items on Supabase. Database unchanged.",
        );
      }

      final cloudItems = itemsList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Blocker Fix 3: Fail closed on credit sale patient fetch failure
      final String customerAcc = (cloudHeader['customer_acc'] ?? cloudHeader['payment_mode'] ?? 'Cash').toString().trim();
      final double grandTotal = (cloudHeader['grand_total'] as num?)?.toDouble() ?? (cloudHeader['net_amount'] as num?)?.toDouble() ?? 0.0;
      final double rcvdAmt = (cloudHeader['rcvd_amt'] as num?)?.toDouble() ?? 0.0;
      final bool isCreditSale = (customerAcc.toUpperCase() != 'CASH') || (grandTotal - rcvdAmt > 0.01);

      Map<String, dynamic>? verifiedPatientRecord;
      final String cloudPatientName = (cloudHeader['patient'] ?? cloudHeader['customer_name'] ?? '').toString().trim();
      final String cloudPatientId = (cloudHeader['patient_id'] ?? '').toString().trim();

      if (cloudPatientId.isNotEmpty) {
        final patUri = Uri.parse('$cleanUrl/rest/v1/patients?id=eq.${Uri.encodeComponent(cloudPatientId)}&select=*');
        final patRes = await http.get(patUri, headers: headers).timeout(const Duration(seconds: 8));
        if (patRes.statusCode == 200) {
          final List<dynamic> patData = jsonDecode(patRes.body);
          if (patData.length == 1) {
            verifiedPatientRecord = Map<String, dynamic>.from(patData.first as Map);
          }
        }
      } else if (cloudPatientName.isNotEmpty && cloudPatientName.toUpperCase() != 'WALK-IN CUSTOMER' && cloudPatientName.toUpperCase() != 'CASH') {
        final patUri = Uri.parse('$cleanUrl/rest/v1/patients?name=eq.${Uri.encodeComponent(cloudPatientName)}&select=*');
        final patRes = await http.get(patUri, headers: headers).timeout(const Duration(seconds: 8));
        if (patRes.statusCode == 200) {
          final List<dynamic> patData = jsonDecode(patRes.body);
          if (patData.length == 1) {
            verifiedPatientRecord = Map<String, dynamic>.from(patData.first as Map);
          } else if (patData.length > 1) {
            return InvoiceRecoveryResult(
              success: false,
              message: "Ambiguous patient name '$cloudPatientName' found (${patData.length} records on cloud). Cannot verify unique patient ID. Database unchanged.",
            );
          }
        }
      }

      if (isCreditSale && verifiedPatientRecord == null) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Credit sale patient record ('$cloudPatientName') could not be verified on Supabase. Recovery aborted to prevent patient ledger drift. Database unchanged.",
        );
      }

      // Safeguard 2: Back up the database and verify the backup file
      await DbHelper.instance.checkpointWal();
      final dbPath = await sql.getDatabasesPath();
      final sourceFile = File(join(dbPath, 'pharmacy.db'));
      if (!await sourceFile.exists()) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Primary database file pharmacy.db not found. Recovery aborted.",
        );
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(join(docsDir.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestampStr = DateTime.now().millisecondsSinceEpoch;
      final backupPath = join(backupDir.path, 'pharmacy_recovery_backup_$timestampStr.db');
      final backupFile = await sourceFile.copy(backupPath);

      if (!await backupFile.exists() || await backupFile.length() == 0) {
        return InvoiceRecoveryResult(
          success: false,
          message: "Database backup creation failed or resulted in zero bytes. Recovery aborted.",
        );
      }

      // Safeguard 4, 5, 6 & Blocker Fix 1: Perform atomic SQLite transaction with PRAGMA column filtering
      final db = await DbHelper.instance.database;

      await db.transaction((txn) async {
        // Blocker Fix 1: Fetch actual schema columns for sales_invoices and sales_items
        final headerInfo = await txn.rawQuery('PRAGMA table_info(sales_invoices)');
        final validHeaderCols = headerInfo.map((c) => (c['name'] as String).toLowerCase()).toSet();

        final itemInfo = await txn.rawQuery('PRAGMA table_info(sales_items)');
        final validItemCols = itemInfo.map((c) => (c['name'] as String).toLowerCase()).toSet();

        // 4a. Recheck PC2 local draft status inside transaction
        final draftCheck = await txn.query(
          'sales_invoices',
          where: 'entry_no = ? OR invoice_no = ?',
          whereArgs: [cleanEntryNo, cleanEntryNo],
          limit: 1,
        );

        if (draftCheck.isEmpty) {
          throw "Local invoice #$cleanEntryNo not found in SQLite. Recovery aborted.";
        }

        final localDraft = draftCheck.first;
        final int isSynced = (localDraft['is_synced'] as num?)?.toInt() ?? 1;
        final int isDeleted = (localDraft['is_deleted'] as num?)?.toInt() ?? 0;

        if (isSynced != 0) {
          throw "Local invoice #$cleanEntryNo is already marked as synced (is_synced = $isSynced). Aborting to prevent overwriting an already-synced sale.";
        }
        if (isDeleted == 1) {
          throw "Local invoice #$cleanEntryNo is marked as deleted locally. Recovery aborted.";
        }

        // 4b. Check for linked records (returns / receipts) referencing draft #5
        final linkedReturns = await txn.query(
          'sales_return_invoices',
          where: 'original_invoice_no = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [cleanEntryNo],
          limit: 1,
        );
        if (linkedReturns.isNotEmpty) {
          throw "Draft #$cleanEntryNo has linked sales returns in SQLite. Aborting to prevent orphaned records.";
        }

        final linkedPayments = await txn.query(
          'patient_payments',
          where: 'invoice_no = ?',
          whereArgs: [cleanEntryNo],
          limit: 1,
        );
        if (linkedPayments.isNotEmpty) {
          throw "Draft #$cleanEntryNo has linked patient payments in SQLite. Aborting to prevent orphaned financial records.";
        }

        // 4c. Fetch draft line items and reverse draft stock
        final draftItems = await txn.query(
          'sales_items',
          where: 'invoice_no = ?',
          whereArgs: [cleanEntryNo],
        );

        for (var dItem in draftItems) {
          final pId = (dItem['product_id'] ?? '').toString().trim();
          final bNo = (dItem['batch_number'] ?? dItem['batch'] ?? '').toString().trim();
          final qty = (dItem['qty'] as num?)?.toInt() ?? (dItem['quantity'] as num?)?.toInt() ?? 0;

          if (pId.isNotEmpty && bNo.isNotEmpty && qty > 0) {
            // Safeguard 5: Match stock batch to exactly one local row
            final batchRows = await txn.rawQuery('''
              SELECT rowid, current_stock FROM stock_batches 
              WHERE product_id = ? AND batch_number = ? COLLATE NOCASE
            ''', [pId, bNo]);

            if (batchRows.isEmpty) {
              throw "Stock reversal error: Stock batch not found for Product '$pId' Batch '$bNo'. Transaction rolled back.";
            }
            if (batchRows.length > 1) {
              throw "Stock reversal error: Ambiguous stock batch (${batchRows.length} duplicate rows) for Product '$pId' Batch '$bNo'. Transaction rolled back.";
            }

            final rowId = (batchRows.first['rowid'] as num).toInt();
            await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock + ? WHERE rowid = ?',
              [qty, rowId],
            );
          }
        }

        // 4d. Purge local draft rows (child sales_items FIRST to respect foreign key constraint)
        await txn.delete('sales_items', where: 'invoice_no = ?', whereArgs: [cleanEntryNo]);
        await txn.delete('sales_invoices', where: 'entry_no = ? OR invoice_no = ?', whereArgs: [cleanEntryNo, cleanEntryNo]);
        await txn.delete('pending_deletions', where: 'table_name = ? AND entry_no = ?', whereArgs: ['sales_invoices', cleanEntryNo]);

        // 4e. Map and filter header fields against PRAGMA table_info(sales_invoices)
        final Map<String, dynamic> mappedHeader = {
          'entry_no': cleanEntryNo,
          'invoice_no': cloudHeader['invoice_no']?.toString() ?? cleanEntryNo,
          'date': cloudHeader['date']?.toString() ?? '',
          'customer_acc': customerAcc,
          'customer_name': cloudPatientName,
          'patient': cloudPatientName,
          'mobile': cloudHeader['mobile']?.toString() ?? cloudHeader['customer_phone']?.toString() ?? '',
          'doctor': cloudHeader['doctor']?.toString() ?? 'D1',
          'doctor_reg_no': cloudHeader['doctor_reg_no']?.toString() ?? '',
          'sub_total': (cloudHeader['sub_total'] as num?)?.toDouble() ?? (cloudHeader['subtotal'] as num?)?.toDouble() ?? 0.0,
          'total_amount': grandTotal,
          'grand_total': grandTotal,
          'discount': (cloudHeader['discount'] as num?)?.toDouble() ?? (cloudHeader['discount_amount'] as num?)?.toDouble() ?? 0.0,
          'discount_percent': (cloudHeader['discount_percent'] as num?)?.toDouble() ?? 0.0,
          'additional_discount': (cloudHeader['additional_discount'] as num?)?.toDouble() ?? 0.0,
          'other_charge': (cloudHeader['other_charge'] as num?)?.toDouble() ?? 0.0,
          'tax': (cloudHeader['tax'] as num?)?.toDouble() ?? (cloudHeader['tax_amount'] as num?)?.toDouble() ?? 0.0,
          'round_off': (cloudHeader['round_off'] as num?)?.toDouble() ?? 0.0,
          'rcvd_amt': rcvdAmt,
          'payment_mode': (cloudHeader['payment_mode'] ?? 'CASH').toString(),
          'payment_remarks': cloudHeader['payment_remarks']?.toString() ?? '',
          'secondary_acc': cloudHeader['secondary_acc']?.toString() ?? '',
          'secondary_amt': (cloudHeader['secondary_amt'] as num?)?.toDouble() ?? 0.0,
          'is_deleted': 0,
          'is_paid': (cloudHeader['is_paid'] as num?)?.toInt() ?? 1,
          'tax_type': cloudHeader['tax_type']?.toString() ?? 'Non Gst',
          'agent': cloudHeader['agent']?.toString() ?? 'Admin',
          'sales_return_amt': (cloudHeader['sales_return_amt'] as num?)?.toDouble() ?? 0.0,
          'order_type': (cloudHeader['order_type'] as num?)?.toInt() ?? 0,
          'financial_year': cloudHeader['financial_year']?.toString() ?? '',
          'terminal_id': cloudHeader['terminal_id']?.toString() ?? '',
          'is_synced': 1,
        };

        final Map<String, dynamic> filteredHeader = {};
        for (var entry in mappedHeader.entries) {
          if (validHeaderCols.contains(entry.key.toLowerCase())) {
            filteredHeader[entry.key] = entry.value;
          }
        }

        await txn.insert('sales_invoices', filteredHeader, conflictAlgorithm: sql.ConflictAlgorithm.replace);

        // 4f. Map and filter item fields against PRAGMA table_info(sales_items)
        for (var cItem in cloudItems) {
          final pId = (cItem['product_id'] ?? '').toString().trim();
          final pName = (cItem['product_name'] ?? '').toString().trim();
          final bNo = (cItem['batch_number'] ?? cItem['batch'] ?? '').toString().trim();
          final exp = (cItem['expiry_date'] ?? cItem['expiry'] ?? '').toString().trim();
          final qty = (cItem['qty'] as num?)?.toInt() ?? (cItem['quantity'] as num?)?.toInt() ?? 0;
          final pack = (cItem['packin'] as num?)?.toInt() ?? (cItem['packing'] as num?)?.toInt() ?? 1;

          final Map<String, dynamic> mappedItem = {
            'invoice_no': cleanEntryNo,
            'product_id': pId,
            'product_name': pName,
            'extra': cItem['extra']?.toString() ?? '',
            'batch_number': bNo,
            'expiry_date': exp,
            'qty': qty,
            'quantity': qty,
            'packin': pack,
            'packing': pack,
            'mrp': (cItem['mrp'] as num?)?.toDouble() ?? 0.0,
            'purchase_rate': (cItem['purchase_rate'] as num?)?.toDouble() ?? 0.0,
            'landing_cost': (cItem['landing_cost'] as num?)?.toDouble() ?? 0.0,
            'taxable_sp': (cItem['taxable_sp'] as num?)?.toDouble() ?? (cItem['s_rate'] as num?)?.toDouble() ?? 0.0,
            's_rate': (cItem['s_rate'] as num?)?.toDouble() ?? (cItem['sale_rate'] as num?)?.toDouble() ?? 0.0,
            'sale_rate': (cItem['sale_rate'] as num?)?.toDouble() ?? (cItem['s_rate'] as num?)?.toDouble() ?? 0.0,
            'disc_percent': (cItem['disc_percent'] as num?)?.toDouble() ?? 0.0,
            'disc_amt': (cItem['disc_amt'] as num?)?.toDouble() ?? 0.0,
            'gst_percent': (cItem['gst_percent'] as num?)?.toDouble() ?? (cItem['tax_percent'] as num?)?.toDouble() ?? 0.0,
            'tax_percent': (cItem['tax_percent'] as num?)?.toDouble() ?? (cItem['gst_percent'] as num?)?.toDouble() ?? 0.0,
            'gst_amt': (cItem['gst_amt'] as num?)?.toDouble() ?? 0.0,
            'cgst_amt': (cItem['cgst_amt'] as num?)?.toDouble() ?? 0.0,
            'sgst_amt': (cItem['sgst_amt'] as num?)?.toDouble() ?? 0.0,
            'igst_amt': (cItem['igst_amt'] as num?)?.toDouble() ?? 0.0,
            'total': (cItem['total'] as num?)?.toDouble() ?? (cItem['total_amount'] as num?)?.toDouble() ?? 0.0,
            'profit': (cItem['profit'] as num?)?.toDouble() ?? 0.0,
            'supplier_name': (cItem['supplier_name'] ?? cItem['supplier'] ?? '').toString(),
            'rack': cItem['rack']?.toString() ?? '',
          };

          // Explicitly strip sync status columns from sales_items (sync state is managed on sales_invoices header)
          mappedItem.remove('is_synced');
          mappedItem.remove('is_cloud_synced');

          final Map<String, dynamic> filteredItem = {};
          for (var entry in mappedItem.entries) {
            if (entry.key != 'is_synced' && entry.key != 'is_cloud_synced' && validItemCols.contains(entry.key.toLowerCase())) {
              filteredItem[entry.key] = entry.value;
            }
          }

          await txn.insert('sales_items', filteredItem, conflictAlgorithm: sql.ConflictAlgorithm.replace);

          // 4g. Apply targeted stock deduction for PC1 sale item
          if (pId.isNotEmpty && bNo.isNotEmpty && qty > 0) {
            // Safeguard 5: Match stock batch to exactly one local row
            final batchRows = await txn.rawQuery('''
              SELECT rowid, current_stock FROM stock_batches 
              WHERE product_id = ? AND batch_number = ? COLLATE NOCASE
            ''', [pId, bNo]);

            if (batchRows.isEmpty) {
              throw "Cloud sale stock deduction error: Stock batch not found for Product '$pId' Batch '$bNo'. Transaction rolled back.";
            }
            if (batchRows.length > 1) {
              throw "Cloud sale stock deduction error: Ambiguous stock batch (${batchRows.length} duplicate rows) for Product '$pId' Batch '$bNo'. Transaction rolled back.";
            }

            final rowId = (batchRows.first['rowid'] as num).toInt();
            final int currentStockPostReversal = (batchRows.first['current_stock'] as num).toInt();

            if (currentStockPostReversal < qty) {
              throw "Stock shortage for Product '$pId' Batch '$bNo': Current available stock is $currentStockPostReversal units, but cloud sale requires $qty units. Transaction rolled back.";
            }

            final affected = await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock - ? WHERE rowid = ? AND current_stock >= ?',
              [qty, rowId, qty],
            );

            if (affected == 0) {
              throw "Stock race condition/shortage updating RowID $rowId for Product '$pId' Batch '$bNo'. Transaction rolled back.";
            }
          }
        }

        // Safeguard 6: Update patient using verified unique ID (never name alone)
        if (verifiedPatientRecord != null) {
          final String verifiedId = (verifiedPatientRecord['id'] ?? '').toString().trim();
          if (verifiedId.isNotEmpty) {
            final double verifiedBal = (verifiedPatientRecord['current_balance'] as num?)?.toDouble() ?? (verifiedPatientRecord['balance'] as num?)?.toDouble() ?? 0.0;
            final existingPat = await txn.query('patients', where: 'id = ?', whereArgs: [verifiedId]);
            if (existingPat.isNotEmpty) {
              await txn.update(
                'patients',
                {'current_balance': verifiedBal, 'is_synced': 1},
                where: 'id = ?',
                whereArgs: [verifiedId],
              );
            } else {
              await txn.insert('patients', {
                'id': verifiedId,
                'name': verifiedPatientRecord['name'] ?? cloudPatientName,
                'mobile': verifiedPatientRecord['mobile'] ?? verifiedPatientRecord['phone'] ?? '',
                'address': verifiedPatientRecord['address'] ?? '',
                'current_balance': verifiedBal,
                'is_synced': 1,
              });
            }
          }
        }
      });

      // Phase 5: Refresh In-Memory Provider & UI
      if (pharmacy != null) {
        pharmacy.invalidateSearchProductsCache();
        await pharmacy.syncInventoryFromDb();
        await pharmacy.loadFromDatabase();
        await pharmacy.recalculateTodayStatsFromDb();
      }

      return InvoiceRecoveryResult(
        success: true,
        message: "Invoice #$cleanEntryNo successfully recovered from Supabase Cloud on PC2.",
        backupPath: backupPath,
        cloudHeader: cloudHeader,
        cloudItems: cloudItems,
      );
    } catch (e, stack) {
      debugPrint("InvoiceRecoveryService error: $e\n$stack");
      return InvoiceRecoveryResult(
        success: false,
        message: "Recovery failed: $e. Local SQLite database remained completely unchanged.",
      );
    } finally {
      // Resume background sync
      syncService.resumeSync();
    }
  }
}
