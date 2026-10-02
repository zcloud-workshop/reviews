import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/home_screen.dart';
import '../services/question_bank_controller.dart';
import '../services/quiz_progress_controller.dart';
import '../theme/app_theme.dart';

class ReviewsApp extends StatefulWidget {
  const ReviewsApp({super.key});

  @override
  State<ReviewsApp> createState() => _ReviewsAppState();
}

class _ReviewsAppState extends State<ReviewsApp> {
  static const _themeModeKey = 'theme_mode';

  SharedPreferences? _preferences;
  late final QuestionBankController _questionBankController;
  late final QuizProgressController _progressController;
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    final systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _themeMode =
        systemBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
    _questionBankController = QuestionBankController();
    _progressController = QuizProgressController();
    _loadThemeMode();
    _questionBankController.load();
    _progressController.load();
  }

  @override
  void dispose() {
    _questionBankController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _loadThemeMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      final savedMode = preferences.getString(_themeModeKey);
      final mode = switch (savedMode) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => null,
      };

      if (mode != null && mounted && mode != _themeMode) {
        setState(() => _themeMode = mode);
      }
    } catch (_) {
      // 本地偏好不可用时继续使用启动时确定的主题，不影响应用使用。
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      return;
    }

    if (mode != _themeMode) {
      setState(() => _themeMode = mode);
    }

    try {
      final preferences = _preferences ?? await SharedPreferences.getInstance();
      _preferences = preferences;
      await preferences.setString(
        _themeModeKey,
        mode == ThemeMode.dark ? 'dark' : 'light',
      );
    } catch (_) {
      // 写入失败不回滚当前主题，用户仍可在本次使用中正常切换。
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reviews',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: HomeScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        progressController: _progressController,
        questionBankController: _questionBankController,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
