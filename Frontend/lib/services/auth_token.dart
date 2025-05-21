String? _jwtAccessToken;

void setStoredAccessToken(String token) {
  _jwtAccessToken = token;
}

String? getStoredAccessToken() {
  return _jwtAccessToken;
}

void clearStoredAccessToken() {
  _jwtAccessToken = null;
}