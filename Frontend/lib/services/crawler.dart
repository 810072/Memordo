// lib/services/crawler.dart
import 'package:flutter/material.dart';

class CrawlerPage extends StatefulWidget {
  final String url;

  const CrawlerPage({Key? key, required this.url}) : super(key: key);

  @override
  State<CrawlerPage> createState() => _CrawlerPageState();
}

class _CrawlerPageState extends State<CrawlerPage> {
  @override
  void initState() {
    super.initState();

    // 1. 전달받은 URL을 콘솔에 출력
    print('URL: ${widget.url}');

    // 2. (선택 사항) 백엔드로 URL 전송 로직 호출
    // _sendUrlToBackend(widget.url);

    // 3. 즉시 이전 화면으로 돌아가기
    // WidgetsBinding.instance.addPostFrameCallback을 사용하여 initState 완료 후 pop 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) { // 위젯이 여전히 마운트된 상태인지 확인
        Navigator.of(context).pop();
      }
    });
  }

  // 백엔드 전송 함수 예시 (실제 구현 필요)
  // Future<void> _sendUrlToBackend(String url) async {
  //   print('백엔드로 URL ($url) 전송 시도...');
  //   // await http.post(...);
  // }

  @override
  Widget build(BuildContext context) {
    // 이 페이지는 사용자에게 보여지지 않고 바로 pop 되므로,
    // 실제 UI를 구성할 필요가 거의 없습니다.
    // 로딩 인디케이터나 빈 컨테이너를 반환할 수 있습니다.
    return const Scaffold(
      body: Center(
        // child: CircularProgressIndicator(), // 짧은 순간 표시될 수 있는 로딩 인디케이터
        child: SizedBox.shrink(), // 또는 완전히 빈 위젯
      ),
    );
  }
}