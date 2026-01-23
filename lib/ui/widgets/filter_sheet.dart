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
  bool? _pixivLoginOk;

  // 🔥 Pixiv 专属状态
  double _minBookmarks = 0;
  String _selectedRankingMode = ''; // 空字符串表示“普通搜索”

  @override
  void initState() {
    super.initState();
    _tempValues = <String, dynamic>{};

    // 1. 复制通用 Filters
    widget.currentValues.forEach((key, value) {
      if (value is List) {
        _tempValues[key] = List<dynamic>.from(value);
      } else {
        _tempValues[key] = value;
      }
    });

    // 2. 初始化 Pixiv 专属状态
    if (_tempValues.containsKey('min_bookmarks')) {
      _minBookmarks = double.tryParse(_tempValues['min_bookmarks'].toString()) ?? 0;
    }

    final mode = _tempValues['mode']?.toString() ?? '';
    if (['daily', 'weekly', 'monthly', 'rookie', 'original', 'male', 'female'].contains(mode)) {
      _selectedRankingMode = mode;
    } else if (mode.startsWith('ranking_')) {
      _selectedRankingMode = mode.replaceFirst('ranking_', '');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

    // 排行榜模式下，锁定普通的 'order' 和 'mode' 筛选，避免冲突
    if (_selectedRankingMode.isNotEmpty) {
      if (k == 'order' || k == 'mode') return true;
    }

    final bool isPrivileged =
        (k == 'order' && v.contains('popular')) || (k == 'mode' && v == 'r18');

    if (!isPrivileged) return false;

    if (!hasCookie) return true;
    if (!loginResolved) return true;
    return !loginOk;
  }

  void _toastLocked(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1400)),
    );
  }

  // 🔥 构建 Pixiv 专属区域 (排行榜 + 收藏数)
  Widget _buildPixivExtras() {
    final bool isRanking = _selectedRankingMode.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Text("排行榜 (Ranking)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildRankingChip('普通搜索', ''),
              _buildRankingChip('日榜', 'daily'),
              _buildRankingChip('周榜', 'weekly'),
              _buildRankingChip('月榜', 'monthly'),
              _buildRankingChip('新人', 'rookie'),
              _buildRankingChip('原创', 'original'),
              _buildRankingChip('受男性欢迎', 'male'),
              _buildRankingChip('受女性欢迎', 'female'),
            ],
          ),
        ),
        Opacity(
          opacity: isRanking ? 0.4 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("最小收藏数 (users入り)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                      _minBookmarks <= 0 ? "不限" : "${_minBookmarks.toInt()}+",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ],
                ),
              ),
              Slider(
                value: _minBookmarks,
                min: 0,
                max: 20000,
                divisions: 20,
                activeColor: Colors.black,
                inactiveColor: Colors.grey[200],
                label: _minBookmarks.toInt().toString(),
                onChanged: isRanking
                    ? null
                    : (v) {
                        setState(() => _minBookmarks = v);
                      },
              ),
            ],
          ),
        ),
        const Divider(height: 24, thickness: 8, color: Color(0xFFF5F5F5)),
      ],
    );
  }

  Widget _buildRankingChip(String label, String modeValue) {
    final bool isSelected = _selectedRankingMode == modeValue;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: Colors.black,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        backgroundColor: Colors.grey[100],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
        onSelected: (val) {
          setState(() {
            if (val) _selectedRankingMode = modeValue;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPixiv = _isPixivActiveSource(context);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                  onPressed: () => setState(() {
                    _tempValues.clear();
                    _minBookmarks = 0;
                    _selectedRankingMode = '';
                  }),
                  child: const Text("重置", style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (isPixiv) _buildPixivExtras(),
                ...widget.filters.map((filter) => _buildFilterGroup(filter)),
              ],
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
                  if (isPixiv) {
                    if (_selectedRankingMode.isNotEmpty) {
                      _tempValues['mode'] = _selectedRankingMode;
                      _tempValues.remove('min_bookmarks');
                    } else {
                      if (_minBookmarks > 0) {
                        _tempValues['min_bookmarks'] = _minBookmarks.toInt();
                      } else {
                        _tempValues.remove('min_bookmarks');
                      }

                      final currentMode = _tempValues['mode']?.toString() ?? '';
                      if (currentMode.startsWith('ranking_') || ['daily', 'weekly'].contains(currentMode)) {
                        _tempValues.remove('mode');
                      }
                    }
                  }

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

    final bool isRankingMode = _selectedRankingMode.isNotEmpty;
    if (isPixiv && isRankingMode && (filter.key == 'mode' || filter.key == 'order')) {
      return const SizedBox();
    }

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
            // ✅ 关键修复点：FilterOption -> SourceFilterOption
            children: filter.options.map<Widget>((SourceFilterOption option) {
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

              final chip = FilterChip(
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
                  onTap: locked ? () => _toastLocked('需要登录') : null,
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