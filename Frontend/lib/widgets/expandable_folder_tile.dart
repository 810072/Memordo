// lib/widgets/expandable_folder_tile.dart
import 'package:flutter/material.dart';

class ExpandableFolderTile extends StatefulWidget {
  final Widget folderIcon;
  final Widget title;
  final List<Widget> children;
  final bool isInitiallyExpanded;
  final Color arrowColor;
  final double itemHeight;
  final VoidCallback? onSelect;
  final bool isSelected;

  const ExpandableFolderTile({
    Key? key,
    required this.folderIcon,
    required this.title,
    required this.children,
    this.isInitiallyExpanded = false,
    this.arrowColor = Colors.grey,
    this.itemHeight = 24.0,
    this.onSelect,
    this.isSelected = false,
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
    widget.onSelect?.call();
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
    final bgColor =
        widget.isSelected
            ? Theme.of(context).primaryColor.withOpacity(0.1)
            : Colors.transparent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bgColor,
          child: InkWell(
            onTap: _handleTap,
            hoverColor: Colors.grey[200],
            splashFactory: NoSplash.splashFactory,
            child: SizedBox(
              height: widget.itemHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
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
                  widget.folderIcon,
                  const SizedBox(width: 4),
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
