// lib/layout/right_sidebar_content.dart
import 'package:flutter/material.dart';
import '../features/meeting_screen.dart'; // For LocalMemo

class RightSidebarContent extends StatelessWidget {
  final bool isLoading;
  final List<LocalMemo> memos;
  final Function(LocalMemo) onMemoTap;
  final VoidCallback onRefresh;

  const RightSidebarContent({
    Key? key,
    required this.isLoading,
    required this.memos,
    required this.onMemoTap,
    required this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250, // Fixed width
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "저장된 메모", // Using existing text
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                  fontFamily: 'Work Sans',
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: "새로고침",
                onPressed: isLoading ? null : onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (memos.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "저장된 메모가 없습니다.\n'.md 파일로 저장' 기능을 사용해보세요.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: memos.length,
                itemBuilder: (context, index) {
                  final memo = memos[index];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onMemoTap(memo),
                        borderRadius: BorderRadius.circular(6.0),
                        hoverColor: const Color(0xFFF1F5F9), // Slate-100
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                            vertical: 10.0,
                          ),
                          child: Text(
                            memo.fileName,
                            style: TextStyle(
                              color: Colors.grey.shade600, // text-slate-600
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Work Sans',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
