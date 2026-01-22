import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/manager/source_manager.dart';
import 'core/services/wallpaper_service.dart';
import 'ui/controllers/home_controller.dart';
import 'ui/pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
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
        Provider(create: (_) => WallpaperService()),

        /// HomeController 需要同时依赖 SourceManager + WallpaperService
        ChangeNotifierProxyProvider2<SourceManager, WallpaperService, HomeController>(
          create: (ctx) => HomeController(
            sourceManager: ctx.read<SourceManager>(),
            service: ctx.read<WallpaperService>(),
          ),
          update: (_, sourceManager, service, controller) {
            controller!.updateDeps(sourceManager: sourceManager, service: service);
            return controller;
          },
        ),
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
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: Colors.black),
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
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