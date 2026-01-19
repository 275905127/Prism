import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/manager/source_manager.dart';
import 'ui/pages/home_page.dart';
import 'core/services/wallpaper_service.dart'; // 引入 Service

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. 设置沉浸式，并预设图标为黑色
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,     // 🔥 Android: 图标变黑
    statusBarBrightness: Brightness.light,        // 🔥 iOS: 图标变黑
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
        // 🔥 新增：注册 WallpaperService
        Provider(create: (_) => WallpaperService()),
      ],
      child: MaterialApp(
        title: 'Prism',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          canvasColor: Colors.white,
          primaryColor: Colors.black,
          cardColor: const Color(0xFFF8F9FA), 

          // 🔥 全局强制 AppBar 的状态栏图标为黑色
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: Colors.black),
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark, // Android 黑图标
              statusBarBrightness: Brightness.light,    // iOS 黑图标
            ),
          ),

          drawerTheme: const DrawerThemeData(
            backgroundColor: Colors.white,
            elevation: 0,
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: Colors.black,
          ),
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
