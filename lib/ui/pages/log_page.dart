import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_log.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  static const String _kLogEnabledKey = 'prism_log_enabled_v1';
  static const String _kLogDebugKey = 'prism_log_debug_enabled_v1';

  bool _logEnabled = true;
  bool _debugEnabled = false;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_kLogEnabledKey);
      final debug = prefs.getBool(_kLogDebugKey);

      _logEnabled = enabled ?? AppLog.I.enabled;
      _debugEnabled = debug ?? AppLog.I.debugEnabled;

      // 立即生效
      AppLog.I.setEnabled(_logEnabled);
      AppLog.I.setDebugEnabled(_debugEnabled);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingPrefs = false);
    }
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLogEnabledKey, _logEnabled);
      await prefs.setBool(_kLogDebugKey, _debugEnabled);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _setLogEnabled(bool v) async {
    setState(() => _logEnabled = v);
    AppLog.I.setEnabled(v);

    // 如果总开关关了，Debug 也没意义（但不强制改状态）
    await _savePrefs();
  }

  Future<void> _setDebugEnabled(bool v) async {
    setState(() => _debugEnabled = v);
    AppLog.I.setDebugEnabled(v);
    await _savePrefs();
  }

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
            onPressed: logs.isEmpty
                ? null
                : () async {
                    final text = logs.join('\n');
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('日志已复制')),
                    );
                  },
          ),
        ],
      ),
      body: _loadingPrefs
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _logEnabled,
                        title: const Text('启用日志'),
                        subtitle: const Text('关闭后将不再写入新日志（日志页仍可查看历史）'),
                        onChanged: (v) => _setLogEnabled(v),
                      ),
                      SwitchListTile(
                        value: _debugEnabled,
                        title: const Text('启用 Debug 细节日志'),
                        subtitle: const Text('开启后会输出 params/headers/body 截断等高频信息，可能刷屏'),
                        onChanged: _logEnabled ? (v) => _setDebugEnabled(v) : null,
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                ),
                Expanded(
                  child: !_logEnabled && logs.isEmpty
                      ? const Center(child: Text('日志已关闭'))
                      : logs.isEmpty
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
                ),
              ],
            ),
    );
  }
}