// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import 'core/engine/rule_engine.dart';
import 'core/manager/source_manager.dart';
import 'core/network/dio_factory.dart';
import 'core/pixiv/pixiv_repository.dart';
import 'core/services/wallpaper_service.dart';
import 'core/storage/preferences_store.dart';
import 'core/utils/prism_logger.dart';
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
        Provider<PrismLogger>(create: (_) => const AppLogLogger()),
        Provider<PreferencesStore>(create: (_) => const PreferencesStore()),
        Provider<DioFactory>(create: (_) => const DioFactory()),

        // Base Dio singleton
        ProxyProvider2<DioFactory, PrismLogger, Dio>(
          update: (_, factory, logger, __) => factory.createBaseDio(logger: logger),
        ),

        // Core engine / repos
        ProxyProvider2<Dio, PrismLogger, RuleEngine>(
          update: (_, dio, logger, __) => RuleEngine(dio: dio, logger: logger),
        ),
        ProxyProvider3<DioFactory, Dio, PrismLogger, PixivRepository>(
          update: (_, factory, baseDio, logger, __) => PixivRepository(
            dio: factory.createPixivDioFrom(baseDio, logger: logger),
            logger: logger,
          ),
        ),

        // ✅ Source manager (no SharedPreferences)
        ChangeNotifierProvider(
          create: (ctx) => SourceManager(
            prefs: ctx.read<PreferencesStore>(),
            logger: ctx.read<PrismLogger>(),
          ),
        ),

        // WallpaperService (UI 唯一入口)
        ProxyProvider5<Dio, RuleEngine, PixivRepository, PreferencesStore, PrismLogger, WallpaperService>(
          update: (_, dio, engine, repo, prefs, logger, __) => WallpaperService(
            dio: dio,
            engine: engine,
            pixivRepo: repo,
            prefs: prefs,
            logger: logger,
          ),
        ),

        /// HomeController 依赖 SourceManager + WallpaperService
        ChangeNotifierProxyProvider2<SourceManager, WallpaperService, HomeController>(
          create: (ctx) => HomeController(
            sourceManager: ctx.read<SourceManager>(),
            service: ctx.read<WallpaperService>(),
            logger: ctx.read<PrismLogger>(),
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