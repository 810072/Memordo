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
         padding: const EdgeInsets.symmetric(horizontal: 8.0),
         textStyle: const TextStyle(fontSize: 12),
         child: child,
       );
}

/// 애니메이션 없이 즉시 나타나는 커스텀 PopupMenuButton
class InstantPopupMenuButton<T> extends PopupMenuButton<T> {
  const InstantPopupMenuButton({
    super.key,
    required super.itemBuilder,
    super.initialValue,
    super.onSelected,
    super.onCanceled,
    super.tooltip,
    super.elevation,
    super.padding,
    super.child,
    super.icon,
    super.iconSize,
    super.offset,
    super.enabled,
    super.shape,
    super.color,
    super.enableFeedback,
    super.constraints,
  });

  @override
  PopupMenuButtonState<T> createState() {
    return _InstantPopupMenuButtonState<T>();
  }
}

/// InstantPopupMenuButton의 상태를 관리하는 클래스
class _InstantPopupMenuButtonState<T> extends PopupMenuButtonState<T> {
  @override
  void showButtonMenu() {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(widget.offset, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero) + widget.offset,
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showInstantMenu<T>(
      context: context,
      elevation: widget.elevation,
      items: widget.itemBuilder(context),
      initialValue: widget.initialValue,
      position: position,
      shape: widget.shape,
      color: widget.color,
      constraints: widget.constraints,
    ).then<void>((T? newValue) {
      if (!mounted) {
        return;
      }
      if (newValue == null) {
        if (widget.onCanceled != null) {
          widget.onCanceled!();
        }
        return;
      }
      if (widget.onSelected != null) {
        widget.onSelected!(newValue);
      }
    });
  }
}

/// 애니메이션 없이 메뉴를 보여주는 커스텀 함수
Future<T?> showInstantMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  ShapeBorder? shape,
  Color? color,
  BoxConstraints? constraints,
  bool useRootNavigator = false,
}) {
  final NavigatorState navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );
  return navigator.push(
    _InstantPopupMenuRoute<T>(
      position: position,
      items: items,
      initialValue: initialValue,
      elevation: elevation,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      shape: shape,
      color: color,
      constraints: constraints,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
    ),
  );
}

/// 애니메이션 시간이 0인 커스텀 팝업 라우트
class _InstantPopupMenuRoute<T> extends PopupRoute<T> {
  _InstantPopupMenuRoute({
    required this.position,
    required this.items,
    this.initialValue,
    this.elevation,
    this.barrierLabel,
    this.shape,
    this.color,
    this.constraints,
    required this.capturedThemes,
  });

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final T? initialValue;
  final double? elevation;
  final ShapeBorder? shape;
  final Color? color;
  final BoxConstraints? constraints;
  final CapturedThemes capturedThemes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  final String? barrierLabel;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Builder(
      builder: (BuildContext context) {
        return CustomSingleChildLayout(
          delegate: _PopupMenuRouteLayout(position, Directionality.of(context)),
          child: capturedThemes.wrap(
            _PopupMenu<T>(route: this, constraints: constraints),
          ),
        );
      },
    );
  }
}

/// 메뉴의 실제 내용을 구성하는 내부 위젯 (Flutter SDK 복사)
class _PopupMenu<T> extends StatelessWidget {
  const _PopupMenu({super.key, required this.route, required this.constraints});

  final _InstantPopupMenuRoute<T> route;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: route.shape,
      color: route.color,
      type: MaterialType.card,
      elevation: route.elevation ?? 8.0,
      child: ConstrainedBox(
        constraints: constraints ?? const BoxConstraints(minWidth: 2.0 * 56.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListBody(children: route.items),
        ),
      ),
    );
  }
}

/// 메뉴의 위치를 계산하는 레이아웃 델리게이트 (Flutter SDK 복사)
class _PopupMenuRouteLayout extends SingleChildLayoutDelegate {
  _PopupMenuRouteLayout(this.position, this.textDirection);

  final RelativeRect position;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  // ✨ [수정] 팝업 위치 결정 로직: 아래 우선, 안되면 위, 그것도 안되면 아래에 붙임
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Calculate the x-coordinate (horizontal position)
    double x;
    if (position.left > position.right) {
      // Anchor is closer to the right edge, so grow to the left.
      x = size.width - position.right - childSize.width;
    } else if (position.left < position.right) {
      // Anchor is closer to the left edge, so grow to the right.
      x = position.left;
    } else {
      // Anchor is equidistant from both edges, so grow in reading direction.
      switch (textDirection) {
        case TextDirection.rtl:
          x = size.width - position.right - childSize.width;
          break;
        case TextDirection.ltr:
          x = position.left;
          break;
      }
    }
    // Ensure x coordinate is within screen bounds
    if (x < 0.0) {
      x = 0.0;
    } else if (x + childSize.width > size.width) {
      x = size.width - childSize.width;
    }

    // --- Y-Position Logic (MODIFIED FOR BELOW PLACEMENT PRIORITY) ---
    // position.bottom is the Y coordinate of the bottom edge of the button.
    // position.top is the Y coordinate of the top edge of the button.
    double y;
    final double yBelow =
        position.bottom; // Potential Y if we put it below the button
    final double yAbove =
        position.top -
        childSize.height; // Potential Y if we put it above the button

    final bool fitsBelow =
        (yBelow + childSize.height) <= size.height; // Check if it fits below
    final bool fitsAbove = yAbove >= 0.0; // Check if it fits above

    if (fitsBelow) {
      // If it fits below, place it there.
      y = yBelow;
    } else if (fitsAbove) {
      // If it doesn't fit below, but fits above, place it there.
      y = yAbove;
    } else {
      // If it fits neither below nor above (e.g., popup is taller than screen space available)
      // Default to placing it aligned with the bottom edge of the screen.
      y = size.height - childSize.height;
      // Prevent negative y coordinate if the popup is taller than the screen
      if (y < 0.0) {
        y = 0.0;
      }
    }
    // --- End of Y-Position Logic Modification ---

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopupMenuRouteLayout oldDelegate) {
    return position != oldDelegate.position ||
        textDirection != oldDelegate.textDirection;
  }
}
