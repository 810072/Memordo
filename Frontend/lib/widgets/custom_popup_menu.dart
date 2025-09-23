// lib/widgets/custom_popup_menu.dart

import 'package:flutter/material.dart';

// 공통으로 사용할 메뉴 아이템의 높이 정의
const double kCompactPopupMenuItemHeight = 32.0;

/// VS Code 스타일의 컴팩트한 PopupMenuItem을 생성하는 공통 위젯
class CompactPopupMenuItem<T> extends PopupMenuItem<T> {
  CompactPopupMenuItem({
    Key? key,
    T? value,
    bool enabled = true,
    required Widget child,
  }) : super(
         key: key,
         value: value,
         enabled: enabled,
         height: kCompactPopupMenuItemHeight, // 높이 고정
         // ✨ [수정] textStyle을 사용하여 폰트 크기만 지정합니다.
         // 이렇게 하면 색상은 현재 테마에서 자동으로 상속받습니다.
         textStyle: const TextStyle(fontSize: 12),
         child: child,
       );
}
