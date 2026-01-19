import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/app_log.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  @override
  Widget build(BuildContext context) {
    final logs = AppLog.I.lines;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              AppLog.I.clear();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清空日志')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final text = logs.join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已复制')),
              );
            },
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (context, i) {
                return SelectableText(
                  logs[i],
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                );
              },
            ),
    );
  }
}