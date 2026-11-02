import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

class CloudBackupService {
  static final CloudBackupService instance = CloudBackupService._internal();
  CloudBackupService._internal();

  /// Creates a local database snapshot in the specified backup directory
  Future<File?> createLocalSnapshot({String? destinationDirPath}) async {
    try {
      final dbPath = await getDatabasesPath();
      final sourcePath = join(dbPath, 'pharmacy.db');
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        debugPrint("Backup Error: Database file not found at $sourcePath");
        return null;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupFileName = 'pharmacy_db_backup_$timestamp.db';

      late Directory backupDir;
      if (destinationDirPath != null && destinationDirPath.isNotEmpty) {
        backupDir = Directory(destinationDirPath);
      } else {
        backupDir = Directory(join(dbPath, 'backups'));
      }

      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final backupFilePath = join(backupDir.path, backupFileName);
      final backupFile = await sourceFile.copy(backupFilePath);

      debugPrint("Backup successful: ${backupFile.path}");
      return backupFile;
    } catch (e) {
      debugPrint("Backup Snapshot Error: $e");
      return null;
    }
  }

  /// Lists all local snapshots sorted by timestamp descending
  Future<List<FileSystemEntity>> listLocalSnapshots({String? destinationDirPath}) async {
    try {
      final dbPath = await getDatabasesPath();
      final backupDir = Directory(destinationDirPath ?? join(dbPath, 'backups'));

      if (!await backupDir.exists()) return [];

      final files = backupDir.listSync().where((f) => f.path.endsWith('.db')).toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (e) {
      debugPrint("List Snapshots Error: $e");
      return [];
    }
  }
}
