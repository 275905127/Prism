import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔥 别忘了引入这个

class FoggyHelper {
  static const Color baseColor = Colors.white;

  static BoxDecoration getDecoration({bool isBottom = false}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: isBottom ? Alignment.bottomCenter : Alignment.topCenter,
        end: isBottom ? Alignment.topCenter : Alignment.bottomCenter,
        colors: [
          baseColor.withOpacity(0.93),
          baseColor.withOpacity(0.93),
          baseColor.withOpacity(0.86),
          baseColor.withOpacity(0.75),
          baseColor.withOpacity(0.50),
          baseColor.withOpacity(0.20),
          baseColor.withOpacity(0.0),
        ],
        stops: const [0.0, 0.4, 0.5, 0.6, 0.75, 0.9, 1.0],
      ),
    );
  }
}

class FoggyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool isScrolled;
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
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      
      // 🔥 核心修改：这里也要显式强制黑图标
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Android 黑图标
        statusBarBrightness: Brightness.light,    // iOS 黑图标
      ),
      
      flexibleSpace: AnimatedOpacity(
        opacity: isScrolled ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Container(
          decoration: FoggyHelper.getDecoration(),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
