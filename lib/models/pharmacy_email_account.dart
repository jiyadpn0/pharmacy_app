class PharmacyProfile {
  final String id;
  final String name;

  PharmacyProfile({required this.id, required this.name});
}

class PharmacyEmailAccount {
  final String profileId;
  final String email;
  final String displayName;
  final String? photoUrl;
  String? refreshToken;
  String? appPassword;
  Map<String, String> authHeaders;
  DateTime? lastTokenRefreshTime;

  PharmacyEmailAccount({
    required this.profileId,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.refreshToken,
    this.appPassword,
    required this.authHeaders,
    this.lastTokenRefreshTime,
  });

  bool get isAppPasswordMode => appPassword != null && appPassword!.trim().isNotEmpty;
}
