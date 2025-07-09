// lib/widgets/expandable_folder_tile.dart
import 'package:flutter/material.dart';

class ExpandableFolderTile extends StatefulWidget {
  final Widget folderIcon;
  final Widget title;
  final List<Widget> children;
  final bool isInitiallyExpanded;
  final Color arrowColor;
  final double itemHeight;

  const ExpandableFolderTile({
    Key? key,
    required this.folderIcon,
    required this.title,
    required this.children,
    this.isInitiallyExpanded = false,
    this.arrowColor = Colors.grey,
    this.itemHeight = 24.0,
  }) : super(key: key);

  @override
  _ExpandableFolderTileState createState() => _ExpandableFolderTileState();
}

class _ExpandableFolderTileState extends State<ExpandableFolderTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isInitiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _heightFactor = _controller.drive(CurveTween(curve: Curves.easeInQuad));

    if (_isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  Widget _buildChildren(BuildContext context, Widget? child) {
    return ClipRect(
      child: Align(heightFactor: _heightFactor.value, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleTap,
            hoverColor: Colors.grey[200],
            splashFactory: NoSplash.splashFactory,
            child: SizedBox(
              height: widget.itemHeight,
              child: Row(
                children: [
                  // 화살표 아이콘을 가장 왼쪽으로 배치하고, 필요에 따라 여백을 조절합니다.
                  SizedBox(
                    width: 20, // 화살표 아이콘이 차지할 고정 너비
                    child: Center(
                      child: Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 16,
                        color: widget.arrowColor,
                      ),
                    ),
                  ),
                  // widget.folderIcon은 이제 왼쪽 들여쓰기만 담당하게 됩니다.
                  widget.folderIcon,
                  // 폴더 아이콘과 제목 사이의 새로운 간격 (기존 2px 제거 후 추가)
                  const SizedBox(
                    width: 4,
                  ), // 폴더 아이콘과 이름 사이의 간격 추가 (기존 2px보다 좀 더 여유있게)
                  Expanded(child: widget.title),
                ],
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _controller.view,
          builder: _buildChildren,
          child: Column(children: widget.children),
        ),
      ],
    );
  }
}
