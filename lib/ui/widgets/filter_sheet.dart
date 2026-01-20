// lib/ui/widgets/filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/manager/source_manager.dart';
import '../../core/models/source_rule.dart';
import '../../core/services/wallpaper_service.dart';

class FilterSheet extends StatefulWidget {
  final List<SourceFilter> filters;
  final Map<String, dynamic> currentValues;
  final ValueChanged<Map<String, dynamic>> onApply;

  const FilterSheet({
    super.key,
    required this.filters,
    required this.currentValues,
    required this.onApply,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Map<String, dynamic> _tempValues;

  Future<bool>? _pixivLoginFuture;
  bool? _pixivLoginOk; // null = 未完成校验；true/false = 已完成

  @override
  void initState() {
    super.initState();
    _tempValues = <String, dynamic>{};
    widget.currentValues.forEach((key, value) {
      if (value is List) {
        _tempValues[key] = List<dynamic>.from(value);
      } else {
        _tempValues[key] = value;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 只在首次进入或依赖变化时触发一次 login 校验（避免 build 里反复请求）
    final activeRule = context.read<SourceManager>().activeRule;
    final service = context.read<WallpaperService>();

    final isPixiv = service.isPixivRule(activeRule);
    if (!isPixiv || activeRule == null) return;

    if (_pixivLoginFuture != null) return;

    _pixivLoginFuture = service.getPixivLoginOk(activeRule).then((ok) {
      if (!mounted) return ok;
      setState(() => _pixivLoginOk = ok);
      return ok;
    }).catchError((_) {
      if (!mounted) return false;
      setState(() => _pixivLoginOk = false);
      return false;
    });
  }

  bool _isPixivActiveSource(BuildContext context) {
    final activeRule = context.read<SourceManager>().activeRule;
    return context.read<WallpaperService>().isPixivRule(activeRule);
  }

  /// Pixiv Cookie 判定包含“规则 headers 自带 Cookie”
  /// 这里只判断“是否提供了 cookie 字符串”，不等价于“有效登录态”
  bool _hasPixivCookie(BuildContext context) {
    final activeRule = context.read<SourceManager>().activeRule;
    if (activeRule == null) return false;

    final headers = context.read<WallpaperService>().getImageHeaders(activeRule);
    final cookie = (headers?['Cookie'] ?? headers?['cookie'] ?? '').trim();
    return cookie.isNotEmpty;
  }

  bool _isOptionLockedForPixiv({
    required String filterKey,
    required String optionValue,
    required bool hasCookie,
    required bool loginOk,
    required bool loginResolved,
  }) {
    final k = filterKey.trim().toLowerCase();
    final v = optionValue.trim().toLowerCase();

    final bool isPrivileged =
        (k == 'order' && v.contains('popular')) || (k == 'mode' && v == 'r18');

    if (!isPrivileged) return false;

    // 规则：
    // - 未提供 cookie：一定锁
    // - 提供 cookie 但 login 未完成校验：保守锁（避免 UI 放行但最终无效）
    // - 校验完成但 loginOk=false：锁
    // - loginOk=true：放行
    if (!hasCookie) return true;
    if (!loginResolved) return true;
    return !loginOk;
  }

  void _toastLocked() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('该筛选项需要有效的 Pixiv 登录 Cookie（未登录/过期会无效）'),
        duration: Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("筛选", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => setState(() => _tempValues.clear()),
                  child: const Text("重置", style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.filters.length,
              itemBuilder: (context, index) {
                final SourceFilter filter = widget.filters[index];
                return _buildFilterGroup(filter);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  widget.onApply(_tempValues);
                  Navigator.pop(context);
                },
                child: const Text("应用", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterGroup(SourceFilter filter) {
    final bool isMulti = filter.type == 'checklist';

    final bool isPixiv = _isPixivActiveSource(context);
    final bool hasCookie = _hasPixivCookie(context);

    final bool loginResolved = _pixivLoginOk != null;
    final bool loginOk = _pixivLoginOk == true;

    // “部分需登录”的提示：如果是 Pixiv 且热门/R18 受限（未登录或未完成校验）就显示
    final bool shouldShowLoginHint = isPixiv &&
        (filter.key.toLowerCase() == 'order' || filter.key.toLowerCase() == 'mode') &&
        (!hasCookie || !loginResolved || !loginOk);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text(filter.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              if (isMulti)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                  child: const Text("多选", style: TextStyle(fontSize: 10, color: Colors.grey)),
                ),
              if (shouldShowLoginHint)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                  child: const Text("部分需登录", style: TextStyle(fontSize: 10, color: Colors.grey)),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: filter.options.map<Widget>((FilterOption option) {
              final dynamic val = _tempValues[filter.key];

              bool isSelected = false;
              if (isMulti) {
                final List<String> list = (val is List) ? val.map((e) => e.toString()).toList() : <String>[];
                isSelected = list.contains(option.value);
              } else {
                isSelected = (val?.toString() ?? '') == option.value;
              }

              final bool locked = isPixiv
                  ? _isOptionLockedForPixiv(
                      filterKey: filter.key,
                      optionValue: option.value,
                      hasCookie: hasCookie,
                      loginOk: loginOk,
                      loginResolved: loginResolved,
                    )
                  : false;

              final FilterChip chip = FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(option.name),
                    if (locked) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                    ],
                  ],
                ),
                selected: isSelected,
                selectedColor: Colors.black,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: locked ? Colors.grey : (isSelected ? Colors.white : Colors.black),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: Colors.grey[100],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide.none,
                ),
                onSelected: locked
                    ? null
                    : (bool selected) {
                        setState(() {
                          if (isMulti) {
                            final List<String> list =
                                (val is List) ? val.map((e) => e.toString()).toList() : <String>[];

                            if (selected) {
                              if (!list.contains(option.value)) list.add(option.value);
                            } else {
                              list.remove(option.value);
                            }
                            _tempValues[filter.key] = list;
                          } else {
                            if (selected) {
                              _tempValues[filter.key] = option.value;
                            } else {
                              _tempValues.remove(filter.key);
                            }
                          }
                        });
                      },
              );

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: locked ? _toastLocked : null,
                  child: Opacity(
                    opacity: locked ? 0.55 : 1.0,
                    child: chip,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}