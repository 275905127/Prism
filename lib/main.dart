// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/manager/source_manager.dart';
import 'ui/pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 开启沉浸式状态栏 (Edge-to-Edge)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    statusBarColor: Colors.transparent,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔥 核心：注入 SourceManager
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SourceManager()),
      ],
      child: MaterialApp(
        title: 'Prism',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        ),
        home: const HomePage(),
      ),
    );
  }
}