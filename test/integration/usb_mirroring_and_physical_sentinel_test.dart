import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempRootDir;
  late Directory primaryBackupsDir;
  late Directory secondaryUsbDir;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRootDir = await Directory.systemTemp.createTemp('pharmacy_usb_test_');
    primaryBackupsDir = Directory(p.join(tempRootDir.path, 'primary_backups'))..createSync();
    secondaryUsbDir = Directory(p.join(tempRootDir.path, 'secondary_usb'))..createSync();

    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DbHelper.instance.setMockDatabase(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS test_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        val REAL
      )
    ''');
    await db.insert('test_data', {'name': 'Inventory Alpha', 'val': 12500.50});
  });

  tearDown(() async {
    DbHelper.instance.setMockDatabase(null);
    await db.close();
    try {
      if (tempRootDir.existsSync()) {
        tempRootDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<File> createTestDbFile(String dirPath, String fileName) async {
    final filePath = p.join(dirPath, fileName);
    final testDb = await databaseFactory.openDatabase(filePath);
    await testDb.execute('CREATE TABLE sample (id INT, item TEXT);');
    await testDb.insert('sample', {'id': 1, 'item': 'Medical Grade Specimen'});
    await testDb.close();
    return File(filePath);
  }

  group('Phase 3: Automated Nightly USB Mirroring & Physical Backup Sentinel Tests', () {
    test('mirrorBackupToSecondaryDrive atomically mirrors verified SQLite database to USB', () async {
      final validSource = await createTestDbFile(primaryBackupsDir.path, 'pharmacy_backup_20261125_120000.db');
      expect(await validSource.exists(), isTrue);

      final mirrorResult = await BackupService.mirrorBackupToSecondaryDrive(
        validSource,
        customSecondaryPath: secondaryUsbDir.path,
        maxBackups: 10,
      );

      expect(mirrorResult.success, isTrue);
      expect(mirrorResult.destinationPath, isNotNull);
      expect(mirrorResult.bytesCopied, greaterThan(0));

      final mirroredFile = File(mirrorResult.destinationPath!);
      expect(await mirroredFile.exists(), isTrue);

      // Verify PRAGMA quick_check integrity of the mirrored file
      final isIntegrityValid = await BackupService.verifyDatabaseIntegrity(mirroredFile);
      expect(isIntegrityValid, isTrue);

      // Verify temporary .tmp file is purged after atomic rename
      final tempFile = File('${mirroredFile.path}.tmp');
      expect(await tempFile.exists(), isFalse);
    });

    test('getPhysicalBackupStatus reports accurate sentinel badges across states', () async {
      // 1. Not configured
      final unconfiguredStatus = await BackupService.getPhysicalBackupStatus(customPath: '');
      expect(unconfiguredStatus.isConfigured, isFalse);
      expect(unconfiguredStatus.healthBadge, equals("NOT CONFIGURED"));

      // 2. Configured but target offline/missing
      final missingDirPath = p.join(tempRootDir.path, 'non_existent_usb_drive');
      final offlineStatus = await BackupService.getPhysicalBackupStatus(customPath: missingDirPath);
      expect(offlineStatus.isConfigured, isTrue);
      expect(offlineStatus.isDriveAccessible, isFalse);
      expect(offlineStatus.healthBadge, equals("DRIVE OFFLINE"));

      // 3. Connected and synced
      final validSource = await createTestDbFile(primaryBackupsDir.path, 'pharmacy_backup_20261125_140000.db');
      await BackupService.mirrorBackupToSecondaryDrive(validSource, customSecondaryPath: secondaryUsbDir.path);

      final activeStatus = await BackupService.getPhysicalBackupStatus(customPath: secondaryUsbDir.path);
      expect(activeStatus.isConfigured, isTrue);
      expect(activeStatus.isDriveAccessible, isTrue);
      expect(activeStatus.totalMirroredFiles, equals(1));
      expect(activeStatus.totalSizeBytes, greaterThan(0));
      expect(activeStatus.lastMirroredAt, isNotNull);
    });

    test('Retention policy purges older backups on secondary USB drive', () async {
      // Create 5 snapshots in secondary USB dir
      for (int i = 1; i <= 5; i++) {
        final f = await createTestDbFile(
          secondaryUsbDir.path,
          'pharmacy_backup_2026112${i}_100000.db',
        );
        // Set slightly older modified date
        await f.setLastModified(DateTime.now().subtract(Duration(days: 6 - i)));
      }

      var currentFiles = await BackupService.getBackupList(customPath: secondaryUsbDir.path);
      expect(currentFiles.length, equals(5));

      // Enforce retention policy with maxBackups = 3
      await BackupService.enforceBackupRetentionPolicy(
        customPath: secondaryUsbDir.path,
        maxBackups: 3,
      );

      final prunedFiles = await BackupService.getBackupList(customPath: secondaryUsbDir.path);
      expect(prunedFiles.length, equals(3));
    });

    test('Corruption defense prevents invalid snapshot from replacing secondary mirror', () async {
      // Create a corrupted fake database file
      final corruptFile = File(p.join(primaryBackupsDir.path, 'corrupted_snapshot.db'))..writeAsStringSync("CORRUPTED_NON_SQLITE_PAYLOAD");

      final result = await BackupService.mirrorBackupToSecondaryDrive(
        corruptFile,
        customSecondaryPath: secondaryUsbDir.path,
      );

      expect(result.success, isFalse);
      expect(result.message, contains("failed integrity check"));

      final targetFile = File(p.join(secondaryUsbDir.path, 'corrupted_snapshot.db'));
      expect(await targetFile.exists(), isFalse);

      final tempFile = File(p.join(secondaryUsbDir.path, 'corrupted_snapshot.db.tmp'));
      expect(await tempFile.exists(), isFalse);
    });
  });
}
