import 'package:flutter/material.dart';
import '../model/token_status_model.dart';
import '../services/auth_token.dart'; // fetchTokenStatus 함수 사용

class TokenStatusProvider with ChangeNotifier {
  TokenStatus? _status;

  TokenStatus? get status => _status;

  bool get isLoaded => _status != null;

  Future<void> loadStatus(BuildContext context) async {
    final data = await fetchTokenStatus(context); // context 전달
    if (data != null) {
      _status = TokenStatus.fromJson(data);
      notifyListeners();
    }
  }

  void clear() {
    _status = null;
    notifyListeners();
  }
}
