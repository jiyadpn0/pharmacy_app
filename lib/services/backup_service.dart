import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

class BackupService {
  static Future<String?> createDatabaseBackup({String? customPath}) async {
    try {
      final dbPath = await getDatabasesPath();
      final sourceFile = File(join(dbPath, 'pharmacy.db'));

      if (!await sourceFile.exists()) {
        debugPrint("Backup Error: Source database pharmacy.db does not exist.");
        return null;
      }

      final backupDir = Directory(customPath ?? join(dbPath, 'Backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupFileName = 'pharmacy_backup_$timestamp.db';
      final backupFile = File(join(backupDir.path, backupFileName));

      // Attempt atomic SQLite VACUUM INTO for zero-corruption WAL mode snapshot
      bool vacuumSuccess = false;
      try {
        final db = await DbHelper.instance.database;
        final escapedPath = backupFile.path.replaceAll("'", "''");
        await db.execute("VACUUM INTO '$escapedPath';");
        vacuumSuccess = await backupFile.exists();
      } catch (vacuumErr) {
        debugPrint("VACUUM INTO fallback triggered: $vacuumErr");
      }

      // Fallback: Checkpoint WAL and copy main database file
      if (!vacuumSuccess) {
        try {
          final db = await DbHelper.instance.database;
          await db.rawQuery('PRAGMA wal_checkpoint(FULL);');
        } catch (e) {
          debugPrint("Checkpoint warning before backup: $e");
        }
        await sourceFile.copy(backupFile.path);
      }

      debugPrint("Database Backup Created Successfully: ${backupFile.path}");
      return backupFile.path;
    } catch (e) {
      debugPrint("Database Backup Failed: $e");
      return null;
    }
  }

  static Future<List<File>> getBackupList({String? customPath}) async {
    try {
      final dbPath = await getDatabasesPath();
      final backupDir = Directory(customPath ?? join(dbPath, 'Backups'));

      if (!await backupDir.exists()) return [];

      final files = await backupDir.list().toList();
      final backupFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();

      backupFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return backupFiles;
    } catch (e) {
      debugPrint("Error fetching backups: $e");
      return [];
    }
  }
}
