import 'package:flutter/material.dart';
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
              setState(() => AppLog.I.clear());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (_, i) => SelectableText(
                logs[i],
                style: const TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
    );
  }
}