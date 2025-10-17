// lib/viewmodels/calendar_sidebar_viewmodel.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/task_model.dart';
import '../model/memo_search_result.dart';

class CalendarSidebarViewModel with ChangeNotifier {
  // 통계 관련
  Map<String, dynamic> _monthlyStats = {
    'daysWithMemo': 0,
    'totalMemos': 0,
    'streak': 0,
    'mostActiveDay': '-',
  };

  // 할일 관련
  List<TaskModel> _tasks = [];

  // 검색 관련
  bool _isSearching = false;
  List<MemoSearchResult> _searchResults = [];
  Map<DateTime, String> _allMemos = {};

  // Getters
  Map<String, dynamic> get monthlyStats => _monthlyStats;
  List<TaskModel> get tasks => _tasks;
  bool get isSearching => _isSearching;
  List<MemoSearchResult> get searchResults => _searchResults;

  int get completedTasksCount => _tasks.where((t) => t.isCompleted).length;

  // ===== 월간 통계 =====

  Future<void> updateStats(DateTime focusedMonth) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('memoData');

    if (jsonString == null) {
      _monthlyStats = {
        'daysWithMemo': 0,
        'totalMemos': 0,
        'streak': 0,
        'mostActiveDay': '-',
      };
      notifyListeners();
      return;
    }

    final Map<String, dynamic> decoded = jsonDecode(jsonString);
    final Map<DateTime, String> memoData = {};
    decoded.forEach((key, value) {
      memoData[DateTime.parse(key)] = value;
    });

    // 현재 월의 메모만 필터링
    final startOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final endOfMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0);

    final monthMemos =
        memoData.entries.where((entry) {
          final date = entry.key;
          return date.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
              date.isBefore(endOfMonth.add(const Duration(days: 1)));
        }).toList();

    // 메모 작성 일수
    final daysWithMemo = monthMemos.length;

    // 총 메모 수 (문자 수 기준)
    final totalMemos = monthMemos.fold<int>(
      0,
      (sum, entry) => sum + entry.value.length,
    );

    // 연속 작성 일수 계산
    final sortedDates = monthMemos.map((e) => e.key).toList()..sort();
    int streak = 0;
    int currentStreak = 0;

    for (int i = 0; i < sortedDates.length; i++) {
      if (i == 0) {
        currentStreak = 1;
      } else {
        final diff = sortedDates[i].difference(sortedDates[i - 1]).inDays;
        if (diff == 1) {
          currentStreak++;
        } else {
          streak = currentStreak > streak ? currentStreak : streak;
          currentStreak = 1;
        }
      }
    }
    streak = currentStreak > streak ? currentStreak : streak;

    // 가장 활발한 요일
    final dayOfWeekCount = <int, int>{};
    for (final entry in monthMemos) {
      final dayOfWeek = entry.key.weekday;
      dayOfWeekCount[dayOfWeek] = (dayOfWeekCount[dayOfWeek] ?? 0) + 1;
    }

    String mostActiveDay = '-';
    if (dayOfWeekCount.isNotEmpty) {
      final maxDay =
          dayOfWeekCount.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;
      final dayNames = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
      mostActiveDay = dayNames[maxDay - 1];
    }

    _monthlyStats = {
      'daysWithMemo': daysWithMemo,
      'totalMemos': totalMemos,
      'streak': streak,
      'mostActiveDay': mostActiveDay,
    };

    // 검색용으로 전체 메모 저장
    _allMemos = memoData;

    notifyListeners();
  }

  // ===== 할일 목록 =====

  Future<void> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('quickTasks');

    if (jsonString != null) {
      final List<dynamic> decoded = jsonDecode(jsonString);
      _tasks = decoded.map((json) => TaskModel.fromJson(json)).toList();
      notifyListeners();
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    await prefs.setString('quickTasks', jsonString);
  }

  void addTask(String title) {
    _tasks.add(
      TaskModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        isCompleted: false,
      ),
    );
    _saveTasks();
    notifyListeners();
  }

  void toggleTask(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        isCompleted: !_tasks[index].isCompleted,
      );
      _saveTasks();
      notifyListeners();
    }
  }

  void deleteTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    _saveTasks();
    notifyListeners();
  }

  void reorderTasks(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final task = _tasks.removeAt(oldIndex);
    _tasks.insert(newIndex, task);
    _saveTasks();
    notifyListeners();
  }

  // ===== 메모 검색 =====

  void searchMemos(String query) {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    final results = <MemoSearchResult>[];
    final lowerQuery = query.toLowerCase();

    _allMemos.forEach((date, content) {
      if (content.toLowerCase().contains(lowerQuery)) {
        results.add(MemoSearchResult(date: date, content: content));
      }
    });

    // 날짜순 정렬 (최신순)
    results.sort((a, b) => b.date.compareTo(a.date));

    _searchResults = results;
    _isSearching = false;
    notifyListeners();
  }
}
