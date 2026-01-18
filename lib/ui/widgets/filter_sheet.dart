import 'package:flutter/material.dart';
import '../../core/models/source_rule.dart';

class FilterSheet extends StatefulWidget {
  final List<SourceFilter> filters;
  final Map<String, dynamic> currentValues;
  final Function(Map<String, dynamic>) onApply;

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
    _tempValues = Map.from(widget.currentValues);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("筛选", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {
                    setState(() => _tempValues.clear()); // 重置
                  },
                  child: const Text("重置", style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // 动态生成筛选组
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.filters.length,
              itemBuilder: (context, index) {
                final filter = widget.filters[index];
                return _buildRadioGroup(filter);
              },
            ),
          ),

          // 确认按钮
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

  Widget _buildRadioGroup(SourceFilter filter) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(filter.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: filter.options.map((option) {
              final isSelected = _tempValues[filter.key] == option.value;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(option.name),
                  selected: isSelected,
                  selectedColor: Colors.black,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.grey[100],
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _tempValues[filter.key] = option.value;
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
