// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/manager/source_manager.dart';
import 'ui/pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. 设置沉浸式状态栏，并强制图标为黑色 (适应白底)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent, // 底部导航栏透明
    statusBarColor: Colors.transparent,           // 顶部状态栏透明
    statusBarIconBrightness: Brightness.dark,     // 🔥 安卓：状态栏图标变黑
    statusBarBrightness: Brightness.light,        // 🔥 iOS：状态栏图标变黑
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SourceManager()),
      ],
      child: MaterialApp(
        title: 'Prism',
        debugShowCheckedModeBanner: false,
        // 🔥 全局纯白主题配置
        theme: ThemeData(
          useMaterial3: true,
          // 背景颜色
          scaffoldBackgroundColor: Colors.white,
          canvasColor: Colors.white, // 侧边栏背景
          primaryColor: Colors.black, // 主要元素颜色（如加载圈）
          
          // 卡片颜色 (极淡的灰，在纯白背景上通过微弱对比显示层级，或者你也可以改成 Colors.white)
          cardColor: const Color(0xFFF5F5F5), 

          // AppBar 主题
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black, // 标题和图标颜色
            elevation: 0,
            scrolledUnderElevation: 0, // 滚动时不改变颜色
            iconTheme: IconThemeData(color: Colors.black),
          ),

          // 侧边栏主题
          drawerTheme: const DrawerThemeData(
            backgroundColor: Colors.white,
            elevation: 0,
          ),

          // 进度条主题
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: Colors.black,
            linearTrackColor: Colors.transparent,
          ),
          
          // 总体配色方案
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.black,
            surface: Colors.white,
            brightness: Brightness.light,
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
