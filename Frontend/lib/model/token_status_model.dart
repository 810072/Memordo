class TokenStatus {
  final bool accessTokenValid;
  final bool refreshTokenValid;
  final bool googleAccessTokenValid;
  final bool googleRefreshTokenValid;

  TokenStatus({
    required this.accessTokenValid,
    required this.refreshTokenValid,
    required this.googleAccessTokenValid,
    required this.googleRefreshTokenValid,
  });

  factory TokenStatus.fromJson(Map<String, dynamic> json) {
    return TokenStatus(
      accessTokenValid: json['accessTokenValid'] ?? false,
      refreshTokenValid: json['refreshTokenValid'] ?? false,
      googleAccessTokenValid: json['googleAccessTokenValid'] ?? false,
      googleRefreshTokenValid: json['googleRefreshTokenValid'] ?? false,
    );
  }
}
