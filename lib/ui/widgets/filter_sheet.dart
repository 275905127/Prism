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

  bool _isPixivActiveSource(BuildContext context) {
    final activeRule = context.read<SourceManager>().activeRule;
    return context.read<WallpaperService>().isPixivRule(activeRule);
  }

  /// ✅ Pixiv Cookie 判定必须包含“规则 headers 自带 Cookie”
  ///
  /// 新实现：直接读取 Service 计算后的最终图片请求头（会触发 _syncPixivCookieFromRule）
  /// 只要最终 headers 里存在 Cookie，即视为“已设置 Cookie”
  ///
  /// 注意：
  /// - Cookie 非空不代表一定已登录（可能过期），但 UI 侧用于“是否允许选择”已足够。
  /// - 登录态由 Repo 侧进一步判定（loginOk），会自动降级 popular/r18 等筛选。
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
  }) {
    if (hasCookie) return false;

    final k = filterKey.trim().toLowerCase();
    final v = optionValue.trim().toLowerCase();

    // 按 Pixiv 官方形态做两档：
    // - 热门排序：需登录
    if (k == 'order' && v.contains('popular')) return true;

    // - R-18：通常需登录（且未登录常导致空/失败/不可见）
    if (k == 'mode' && v == 'r18') return true;

    return false;
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
              if (isPixiv && !hasCookie && (filter.key.toLowerCase() == 'order' || filter.key.toLowerCase() == 'mode'))
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
                    )
                  : false;

              // 置灰：禁用 onSelected，但保留点击提示
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