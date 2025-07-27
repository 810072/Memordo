class TokenStatus {
  final bool accessTokenValid;
  final bool refreshTokenValid;
  final bool googleAccessTokenValid;
  final bool googleRefreshTokenValid;
  final String? userName; // ✨ 추가
  final String? profileImageUrl; // ✨ 추가

  TokenStatus({
    required this.accessTokenValid,
    required this.refreshTokenValid,
    required this.googleAccessTokenValid,
    required this.googleRefreshTokenValid,
    this.userName, // ✨ 추가
    this.profileImageUrl, // ✨ 추가
  });

  factory TokenStatus.fromJson(Map<String, dynamic> json) {
    return TokenStatus(
      accessTokenValid: json['accessTokenValid'] ?? false,
      refreshTokenValid: json['refreshTokenValid'] ?? false,
      googleAccessTokenValid: json['googleAccessTokenValid'] ?? false,
      googleRefreshTokenValid: json['googleRefreshTokenValid'] ?? false,
      userName: json['userName'], // ✨ 추가
      profileImageUrl: json['profileImageUrl'], // ✨ 추가
    );
  }

  Map<String, dynamic> toJson() => {
    'accessTokenValid': accessTokenValid,
    'refreshTokenValid': refreshTokenValid,
    'googleAccessTokenValid': googleAccessTokenValid,
    'googleRefreshTokenValid': googleRefreshTokenValid,
    'userName': userName, // ✨ 추가
    'profileImageUrl': profileImageUrl, // ✨ 추가
  };

  bool get isFullyAuthenticated => accessTokenValid;
  bool get isGoogleLinked => googleAccessTokenValid || googleRefreshTokenValid;
}
