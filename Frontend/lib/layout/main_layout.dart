// lib/layout/main_layout.dart
import 'package:flutter/material.dart';
import 'left_sidebar_content.dart';
import '../features/page_type.dart'; // PageType enum을 별도 파일로 분리하거나, 여기에 정의

class MainLayout extends StatefulWidget {
  final Widget child;
  final Widget? rightSidebarChild;
  final PageType activePage;

  const MainLayout({
    Key? key,
    required this.child,
    required this.activePage,
    this.rightSidebarChild,
  }) : super(key: key);

  @override
  _MainLayoutState createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isLeftExpanded = true;
  bool _isRightExpanded = true;

  void _toggleLeftPanel() {
    setState(() {
      _isLeftExpanded = !_isLeftExpanded;
    });
  }

  void _toggleRightPanel() {
    setState(() {
      _isRightExpanded = !_isRightExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showRightPanelButton = widget.rightSidebarChild != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // bg-slate-100
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1.0,
        shadowColor: Colors.black12,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.menu,
            color: Color(0xFF475569),
          ), // text-slate-600
          onPressed: _toggleLeftPanel,
          tooltip: 'Toggle Sidebar',
        ),
        title: Row(
          children: const [
            Icon(
              Icons.note_alt_rounded,
              color: Color(0xFF3d98f4),
            ), // Updated Icon
            SizedBox(width: 8),
            Text(
              'Memordo',
              style: TextStyle(
                color: Color(0xFF1E293B), // text-slate-800
                fontWeight: FontWeight.w600,
                fontSize: 20,
                fontFamily: 'Work Sans',
              ),
            ),
          ],
        ),
        actions: [
          if (showRightPanelButton)
            IconButton(
              icon: const Icon(
                Icons.menu_open_outlined,
                color: Color(0xFF475569),
              ), // Updated Icon
              onPressed: _toggleRightPanel,
              tooltip: 'Toggle Memos',
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor: Colors.grey.shade300,
              child: Icon(Icons.person_outline, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Row(
        children: [
          // Left Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: _isLeftExpanded ? 240 : 65, // Adjusted widths
            child: LeftSidebarContent(
              isExpanded: _isLeftExpanded,
              activePage: widget.activePage,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
            ),
          ),
          // Main Content
          Expanded(
            child: ClipRect(
              // Avoids overflow during animation
              child: widget.child,
            ),
          ),
          // Right Sidebar
          if (widget.rightSidebarChild != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: _isRightExpanded ? 250 : 0,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: Colors.grey.shade200)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: Offset(-1, 0),
                  ),
                ],
              ),
              child: ClipRect(
                // Hides content when collapsed
                child: widget.rightSidebarChild!,
              ),
            ),
        ],
      ),
    );
  }
}
