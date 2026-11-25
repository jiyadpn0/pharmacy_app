/// Centralized ERP Input Validation Layer for Pharmaceutical Retail & Wholesale.
///
/// Provides strict, statutory validations for Indian GSTINs, PAN, Drug Licenses (Form 20/21),
/// Doctor Registration numbers, Indian phone numbers, Batch numbers, HSN/SAC codes, and Expiry dates.
class AppValidators {
  AppValidators._();

  // --- GSTIN & TAX VALIDATIONS ---

  /// Validates standard 15-character Indian Goods and Services Tax Identification Number (GSTIN).
  ///
  /// Format:
  /// - First 2 digits: State code (01 to 38, or 97/99)
  /// - Next 10 chars: Permanent Account Number (PAN)
  /// - 13th char: Entity code (1-9 or A-Z)
  /// - 14th char: Default 'Z'
  /// - 15th char: Alphanumeric check digit
  static bool isValidGstin(String? gstin) {
    if (gstin == null) return false;
    final clean = gstin.trim().toUpperCase();
    if (clean.length != 15) return false;
    final gstRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
    if (!gstRegex.hasMatch(clean)) return false;

    // Validate state code range (01 to 38, or 97 for Other Territory, 99 for Center)
    final stateCode = int.tryParse(clean.substring(0, 2));
    if (stateCode == null) return false;
    if ((stateCode >= 1 && stateCode <= 38) || stateCode == 97 || stateCode == 99) {
      return true;
    }
    return false;
  }

  /// Validates 10-character Indian Permanent Account Number (PAN).
  ///
  /// Format: 5 uppercase letters, 4 digits, 1 uppercase letter (e.g. `ABCDE1234F`).
  static bool isValidPan(String? pan) {
    if (pan == null) return false;
    final clean = pan.trim().toUpperCase();
    if (clean.length != 10) return false;
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(clean);
  }

  /// Validates 4, 6, or 8-digit HSN (Harmonized System of Nomenclature) or SAC Code.
  static bool isValidHsn(String? hsn) {
    if (hsn == null) return false;
    final clean = hsn.trim();
    if (clean.length != 4 && clean.length != 6 && clean.length != 8) return false;
    return RegExp(r'^[0-9]+$').hasMatch(clean);
  }

  // --- IDENTITY & REGISTRATION VALIDATIONS ---

  /// Validates 10-digit Indian Mobile Number (supports optional '+91' or '0' prefix).
  static bool isValidPhone(String? phone) {
    if (phone == null) return false;
    var clean = phone.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (clean.startsWith('+91')) {
      clean = clean.substring(3);
    } else if (clean.startsWith('91') && clean.length == 12) {
      clean = clean.substring(2);
    } else if (clean.startsWith('0') && clean.length == 11) {
      clean = clean.substring(1);
    }

    if (clean.length != 10) return false;
    return RegExp(r'^[6-9][0-9]{9}$').hasMatch(clean);
  }

  /// Sanitizes phone number to standard 10-digit string or returns empty if invalid.
  static String sanitizePhone(String? phone) {
    if (phone == null) return '';
    var clean = phone.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (clean.startsWith('+91')) {
      clean = clean.substring(3);
    } else if (clean.startsWith('91') && clean.length == 12) {
      clean = clean.substring(2);
    } else if (clean.startsWith('0') && clean.length == 11) {
      clean = clean.substring(1);
    }
    return isValidPhone(clean) ? clean : '';
  }

  /// Validates State Drug Control Drug License Number (Form 20, 20B, 21, 21B).
  ///
  /// Examples: `KL-TVM-12345`, `DL-20B-98765`, `MH-NZ-1234/20`.
  /// Must be alphanumeric, allows hyphens and forward slashes, length 5 to 35 chars.
  static bool isValidDrugLicense(String? dl) {
    if (dl == null) return false;
    final clean = dl.trim().toUpperCase();
    if (clean.length < 5 || clean.length > 60) return false;
    return RegExp(r'^[A-Z0-9\/\-_ ,]+$').hasMatch(clean) && RegExp(r'[0-9]').hasMatch(clean);
  }

  /// Validates Doctor Medical Council Registration Number (e.g. `KMC-12345`, `MCI-54321`, `NMC/9876`).
  static bool isValidDoctorRegNo(String? regNo) {
    if (regNo == null) return false;
    final clean = regNo.trim().toUpperCase();
    if (clean.length < 3 || clean.length > 30) return false;
    return RegExp(r'^[A-Z0-9\/\-_ ]+$').hasMatch(clean);
  }

  /// Validates Pharmaceutical Batch Number.
  ///
  /// Batch numbers must be 1 to 25 characters, non-empty, and without dangerous control chars.
  static bool isValidBatchNumber(String? batch) {
    if (batch == null) return false;
    final clean = batch.trim();
    if (clean.isEmpty || clean.length > 25) return false;
    return RegExp(r'^[A-Za-z0-9\/\-_\.]+$').hasMatch(clean);
  }

  // --- EXPIRY & DATE VALIDATIONS ---

  /// Validates expiry string in `MM/YY`, `MM/YYYY`, `YYYY-MM`, or `YYYY-MM-DD` formats.
  static bool isValidExpiry(String? expiry) {
    if (expiry == null) return false;
    return parseExpiryToDate(expiry) != null;
  }

  /// Parses diverse pharmaceutical expiry formats into the exact last day of the expiry month/date.
  ///
  /// Supports:
  /// - `MM/YY` -> e.g. `05/26` -> `2026-05-31 23:59:59`
  /// - `MM/YYYY` -> e.g. `05/2026` -> `2026-05-31 23:59:59`
  /// - `YYYY-MM-DD` -> e.g. `2026-05-15` -> `2026-05-15 23:59:59`
  /// - `YYYY-MM` -> e.g. `2026-05` -> `2026-05-31 23:59:59`
  static DateTime? parseExpiryToDate(String? expiry) {
    if (expiry == null) return null;
    final clean = expiry.trim();
    if (clean.isEmpty) return null;

    try {
      // 1. Slash formatted: MM/YY or MM/YYYY
      if (clean.contains('/')) {
        final parts = clean.split('/');
        if (parts.length != 2) return null;

        final month = int.tryParse(parts[0]);
        var year = int.tryParse(parts[1]);
        if (month == null || year == null || month < 1 || month > 12) return null;

        if (year < 100) {
          year += 2000;
        }

        // Compute last day of the month
        final nextMonth = month == 12 ? 1 : month + 1;
        final nextYear = month == 12 ? year + 1 : year;
        final lastDay = DateTime(nextYear, nextMonth, 0, 23, 59, 59);
        return lastDay;
      }

      // 2. ISO formatted: YYYY-MM-DD or YYYY-MM
      if (clean.contains('-')) {
        final parts = clean.split('-');
        if (parts.length == 3) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final day = int.tryParse(parts[2]);
          if (year == null || month == null || day == null) return null;
          if (month < 1 || month > 12 || day < 1 || day > 31) return null;
          return DateTime(year, month, day, 23, 59, 59);
        } else if (parts.length == 2) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          if (year == null || month == null || month < 1 || month > 12) return null;
          final nextMonth = month == 12 ? 1 : month + 1;
          final nextYear = month == 12 ? year + 1 : year;
          return DateTime(nextYear, nextMonth, 0, 23, 59, 59);
        }
      }
    } catch (_) {}

    return null;
  }

  /// Determines if a drug batch is expired relative to [asOf] (defaults to current system time).
  static bool isExpired(String? expiry, {DateTime? asOf}) {
    final parsedDate = parseExpiryToDate(expiry);
    if (parsedDate == null) return false;
    final now = asOf ?? DateTime.now();
    return parsedDate.isBefore(now);
  }

  /// Determines if a drug batch is near expiry within [thresholdDays] (default 90 days).
  static bool isNearExpiry(String? expiry, {int thresholdDays = 90, DateTime? asOf}) {
    final parsedDate = parseExpiryToDate(expiry);
    if (parsedDate == null) return false;
    final now = asOf ?? DateTime.now();
    if (parsedDate.isBefore(now)) return false; // Already expired

    final differenceInDays = parsedDate.difference(now).inDays;
    return differenceInDays >= 0 && differenceInDays <= thresholdDays;
  }
}
