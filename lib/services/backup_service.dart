import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

/// Detailed result of a physical backup mirroring operation to USB / external storage.
class BackupMirrorResult {
  final bool success;
  final String? destinationPath;
  final int bytesCopied;
  final String message;
  final String? error;

  const BackupMirrorResult({
    required this.success,
    this.destinationPath,
    this.bytesCopied = 0,
    required this.message,
    this.error,
  });

  Map<String, dynamic> toMap() => {
        'success': success,
        'destination_path': destinationPath,
        'bytes_copied': bytesCopied,
        'message': message,
        'error': error,
      };
}

/// Real-time sentinel status for physical USB and secondary removable storage.
class PhysicalBackupStatus {
  final bool isConfigured;
  final String targetPath;
  final bool isDriveAccessible;
  final File? lastMirroredFile;
  final DateTime? lastMirroredAt;
  final int totalMirroredFiles;
  final int totalSizeBytes;
  final bool isSyncedWithPrimary;
  final String statusMessage;

  const PhysicalBackupStatus({
    required this.isConfigured,
    required this.targetPath,
    required this.isDriveAccessible,
    this.lastMirroredFile,
    this.lastMirroredAt,
    this.totalMirroredFiles = 0,
    this.totalSizeBytes = 0,
    required this.isSyncedWithPrimary,
    required this.statusMessage,
  });

  String get healthBadge {
    if (!isConfigured) return "NOT CONFIGURED";
    if (!isDriveAccessible) return "DRIVE OFFLINE";
    if (!isSyncedWithPrimary) return "SYNC PENDING";
    return "PLUGGED IN & SYNCED";
  }

  double get totalSizeMb => totalSizeBytes / (1024 * 1024);
}

class BackupService {
  /// Scans Windows removable drive mount letters (D: through U:) for accessible storage volumes
  static Future<List<String>> detectRemovableDrives() async {
    final List<String> availableDrives = [];
    if (!Platform.isWindows) return availableDrives;

    for (final letter in ['D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'U']) {
      try {
        final driveDir = Directory('$letter:\\');
        if (await driveDir.exists()) {
          availableDrives.add('$letter:\\');
        }
      } catch (_) {}
    }
    return availableDrives;
  }

  /// Resolves the configured secondary USB destination or auto-locates a connected USB drive
  static Future<String?> getEffectiveSecondaryBackupPath() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getString('secondary_backup_path') ?? '';
    if (configured.isNotEmpty) {
      return configured;
    }

    if (Platform.isWindows) {
      for (final letter in ['D', 'E', 'F', 'G', 'H', 'U']) {
        try {
          final testDir = Directory('$letter:\\Pharmacy_Backups');
          if (await testDir.exists()) {
            return testDir.path;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  /// Creates a primary local SQLite database snapshot and mirrors it to USB / secondary storage
  static Future<String?> createDatabaseBackup({
    String? customPath,
    bool mirrorToSecondary = true,
  }) async {
    try {
      final dbPath = await getDatabasesPath();
      final sourceFile = File(join(dbPath, 'pharmacy.db'));

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
        if (!await sourceFile.exists()) {
          debugPrint("Backup Error: Source database pharmacy.db does not exist and VACUUM INTO failed.");
          return null;
        }
        try {
          final db = await DbHelper.instance.database;
          await db.rawQuery('PRAGMA wal_checkpoint(FULL);');
        } catch (e) {
          debugPrint("Checkpoint warning before backup: $e");
        }
        await sourceFile.copy(backupFile.path);
      }

      // Validate integrity of the created snapshot
      final isValid = await verifyDatabaseIntegrity(backupFile);
      if (!isValid) {
        debugPrint("Primary backup snapshot failed SQLite integrity check, removing corrupt file.");
        if (await backupFile.exists()) await backupFile.delete();
        return null;
      }

      debugPrint("Database Backup Created Successfully: ${backupFile.path}");

      final prefs = await SharedPreferences.getInstance();
      final retentionDays = prefs.getInt('backup_retention_days') ?? 30;
      await enforceBackupRetentionPolicy(customPath: customPath, maxBackups: retentionDays > 0 ? retentionDays : 9999);

      // Automated Physical USB Mirroring Sentinel
      if (mirrorToSecondary) {
        try {
          final mirrorRes = await mirrorBackupToSecondaryDrive(
            backupFile,
            maxBackups: retentionDays > 0 ? retentionDays : 9999,
          );
          if (mirrorRes.success) {
            debugPrint("🛡️ Physical USB Mirror Sentinel: ${mirrorRes.message}");
          } else {
            debugPrint("⚠️ Physical USB Mirror Notice: ${mirrorRes.message}");
          }
        } catch (mirrorErr) {
          debugPrint("Physical USB mirroring non-blocking notice: $mirrorErr");
        }
      }

      return backupFile.path;
    } catch (e) {
      debugPrint("Database Backup Failed: $e");
      return null;
    }
  }

  /// Mirrors a validated snapshot to a secondary USB / external removable drive atomically
  static Future<BackupMirrorResult> mirrorBackupToSecondaryDrive(
    File sourceBackupFile, {
    String? customSecondaryPath,
    int maxBackups = 30,
  }) async {
    try {
      if (!await sourceBackupFile.exists()) {
        return const BackupMirrorResult(
          success: false,
          message: "Source backup file does not exist",
        );
      }

      final targetDirPath = customSecondaryPath ?? await getEffectiveSecondaryBackupPath();
      if (targetDirPath == null || targetDirPath.isEmpty) {
        return const BackupMirrorResult(
          success: false,
          message: "No secondary USB / external destination configured or connected",
        );
      }

      final targetDir = Directory(targetDirPath);
      if (!await targetDir.exists()) {
        try {
          await targetDir.create(recursive: true);
        } catch (e) {
          return BackupMirrorResult(
            success: false,
            message: "Secondary USB destination is inaccessible: $e",
            error: e.toString(),
          );
        }
      }

      final fileName = basename(sourceBackupFile.path);
      final tempTarget = File(join(targetDir.path, '$fileName.tmp'));
      final finalTarget = File(join(targetDir.path, fileName));

      // 1. Copy to temp file first to prevent half-written files on sudden USB unplug
      await sourceBackupFile.copy(tempTarget.path);

      // 2. Verify temp file quick_check before renaming
      final isHealthy = await verifyDatabaseIntegrity(tempTarget);
      if (!isHealthy) {
        try {
          if (await tempTarget.exists()) await tempTarget.delete();
        } catch (delErr) {
          debugPrint("Notice cleaning corrupt temp file: $delErr");
        }
        return const BackupMirrorResult(
          success: false,
          message: "Mirrored snapshot failed integrity check on secondary drive",
        );
      }

      // 3. Atomic rename
      if (await finalTarget.exists()) {
        await finalTarget.delete();
      }
      await tempTarget.rename(finalTarget.path);

      final fileSize = await finalTarget.length();
      debugPrint("Secondary USB mirror created successfully: ${finalTarget.path} ($fileSize bytes)");

      // 4. Enforce retention policy on secondary destination
      await enforceBackupRetentionPolicy(customPath: targetDir.path, maxBackups: maxBackups);

      return BackupMirrorResult(
        success: true,
        destinationPath: finalTarget.path,
        bytesCopied: fileSize,
        message: "Snapshot mirrored successfully to ${finalTarget.path}",
      );
    } catch (e) {
      debugPrint("Error mirroring to secondary drive: $e");
      return BackupMirrorResult(
        success: false,
        message: "Secondary mirror failed: $e",
        error: e.toString(),
      );
    }
  }

  /// Inspects physical USB / secondary destination and evaluates live mirroring health
  static Future<PhysicalBackupStatus> getPhysicalBackupStatus({String? customPath}) async {
    try {
      final effectivePath = customPath ?? await getEffectiveSecondaryBackupPath();
      if (effectivePath == null || effectivePath.isEmpty) {
        return const PhysicalBackupStatus(
          isConfigured: false,
          targetPath: '',
          isDriveAccessible: false,
          isSyncedWithPrimary: false,
          statusMessage: "No secondary USB / external folder configured",
        );
      }

      final dir = Directory(effectivePath);
      final isAccessible = await dir.exists();
      if (!isAccessible) {
        return PhysicalBackupStatus(
          isConfigured: true,
          targetPath: effectivePath,
          isDriveAccessible: false,
          isSyncedWithPrimary: false,
          statusMessage: "Target folder is offline or removable drive is disconnected",
        );
      }

      final secondaryFiles = await getBackupList(customPath: effectivePath);
      final primaryFiles = await getBackupList();

      File? lastFile;
      DateTime? lastTime;
      int totalBytes = 0;

      if (secondaryFiles.isNotEmpty) {
        lastFile = secondaryFiles.first;
        try {
          lastTime = lastFile.lastModifiedSync();
        } catch (_) {
          lastTime = await lastFile.lastModified();
        }
        for (final f in secondaryFiles) {
          try {
            totalBytes += f.lengthSync();
          } catch (_) {
            totalBytes += await f.length();
          }
        }
      }

      bool synced = false;
      if (primaryFiles.isNotEmpty && secondaryFiles.isNotEmpty) {
        synced = basename(primaryFiles.first.path) == basename(secondaryFiles.first.path);
      } else if (primaryFiles.isEmpty && secondaryFiles.isEmpty) {
        synced = true;
      }

      return PhysicalBackupStatus(
        isConfigured: true,
        targetPath: effectivePath,
        isDriveAccessible: true,
        lastMirroredFile: lastFile,
        lastMirroredAt: lastTime,
        totalMirroredFiles: secondaryFiles.length,
        totalSizeBytes: totalBytes,
        isSyncedWithPrimary: synced,
        statusMessage: synced
            ? "USB Mirror is fully up to date (${secondaryFiles.length} backups stored)"
            : "Primary backup has new snapshot pending mirror to USB",
      );
    } catch (e) {
      return PhysicalBackupStatus(
        isConfigured: false,
        targetPath: '',
        isDriveAccessible: false,
        isSyncedWithPrimary: false,
        statusMessage: "Error reading physical backup status: $e",
      );
    }
  }

  /// Verifies SQLite database file health using magic header bytes and PRAGMA quick_check
  static Future<bool> verifyDatabaseIntegrity(File dbFile) async {
    Database? testDb;
    try {
      if (!await dbFile.exists()) return false;
      final length = await dbFile.length();
      if (length < 100) return false;

      // Fast check for SQLite format 3 header to prevent locking corrupted files on Windows
      final raf = await dbFile.open(mode: FileMode.read);
      try {
        final header = await raf.read(16);
        const sqliteHeader = [0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00];
        if (header.length < 16) return false;
        for (int i = 0; i < 16; i++) {
          if (header[i] != sqliteHeader[i]) return false;
        }
      } finally {
        await raf.close();
      }

      testDb = await openDatabase(dbFile.path, readOnly: true);
      final result = await testDb.rawQuery('PRAGMA quick_check;');
      if (result.isNotEmpty && result.first.values.first.toString().toLowerCase() == 'ok') {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Integrity Check Failed for ${dbFile.path}: $e");
      return false;
    } finally {
      try {
        await testDb?.close();
      } catch (_) {}
    }
  }

  /// Restores a selected database backup after validating its integrity
  static Future<bool> restoreDatabaseBackup(File backupFile) async {
    try {
      if (!await verifyDatabaseIntegrity(backupFile)) {
        debugPrint("Restore Aborted: Selected backup file failed integrity check.");
        return false;
      }

      final dbPath = await getDatabasesPath();
      final targetFile = File(join(dbPath, 'pharmacy.db'));

      // Close current DB connection & checkpoint WAL
      await DbHelper.instance.close();

      await backupFile.copy(targetFile.path);
      debugPrint("Database Restored Successfully from ${backupFile.path}");
      return true;
    } catch (e) {
      debugPrint("Database Restore Failed: $e");
      return false;
    }
  }

  /// Auto-cleans backups keeping the latest maxBackups (default: 30)
  static Future<void> enforceBackupRetentionPolicy({String? customPath, int maxBackups = 30}) async {
    try {
      final backupList = await getBackupList(customPath: customPath);
      if (backupList.length > maxBackups) {
        final toDelete = backupList.sublist(maxBackups);
        for (var file in toDelete) {
          if (await file.exists()) {
            await file.delete();
            debugPrint("Cleaned old backup file: ${file.path}");
          }
        }
      }
    } catch (e) {
      debugPrint("Error enforcing retention policy: $e");
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
