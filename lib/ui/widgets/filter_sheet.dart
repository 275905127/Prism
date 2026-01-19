// lib/ui/widgets/filter_sheet.dart
import 'package:flutter/material.dart';
import '../../core/models/source_rule.dart';

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
    // 深拷贝：避免直接改引用
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
                )
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
                // 多选：强制成 List<String>，避免 Object/dynamic 漂移
                final List<String> list = (val is List)
                    ? val.map((e) => e.toString()).toList()
                    : <String>[];
                isSelected = list.contains(option.value);
              } else {
                // 单选：统一按字符串比较更稳
                isSelected = (val?.toString() ?? '') == option.value;
              }

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(option.name),
                  selected: isSelected,
                  selectedColor: Colors.black,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.grey[100],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide.none,
                  ),
                  onSelected: (bool selected) {
                    setState(() {
                      if (isMulti) {
                        final List<String> list = (val is List)
                            ? val.map((e) => e.toString()).toList()
                            : <String>[];

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
                          // 再点一次取消选择（可选行为，留着更通用）
                          _tempValues.remove(filter.key);
                        }
                      }
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}