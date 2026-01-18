// lib/ui/widgets/foggy_app_bar.dart
import 'package:flutter/material.dart';

/// 统一的雾化渐变工具类
class FoggyHelper {
  // 定义基础颜色，方便以后统一修改
  static const Color baseColor = Colors.white;

  // 获取雾化渐变 Decoration (给详情页用)
  static BoxDecoration getDecoration({bool isBottom = false}) {
    // 你的那段经典渐变逻辑
    return BoxDecoration(
      gradient: LinearGradient(
        begin: isBottom ? Alignment.bottomCenter : Alignment.topCenter,
        end: isBottom ? Alignment.topCenter : Alignment.bottomCenter,
        colors: [
          baseColor.withOpacity(0.94),
          baseColor.withOpacity(0.94),
          baseColor.withOpacity(0.90),
          baseColor.withOpacity(0.75),
          baseColor.withOpacity(0.50),
          baseColor.withOpacity(0.20),
          baseColor.withOpacity(0.0),
        ],
        stops: const [0.0, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
      ),
    );
  }
}

/// 统一的雾化 AppBar 组件 (给首页用)
class FoggyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool isScrolled; // 控制是否显示雾化
  final bool centerTitle;

  const FoggyAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.isScrolled = false,
    this.centerTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      centerTitle: centerTitle,
      actions: actions,
      leading: leading,
      // 🔥 核心样式统一在这里
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: AnimatedOpacity(
        opacity: isScrolled ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Container(
          decoration: FoggyHelper.getDecoration(), // 复用上面的逻辑
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
