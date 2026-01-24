enum EngineType { ruleJson, scriptJs, wasm, dartEval }

EngineType? engineTypeFromString(String v) {
  switch (v) {
    case 'rule-json':
      return EngineType.ruleJson;
    case 'script-js':
      return EngineType.scriptJs;
    case 'wasm':
      return EngineType.wasm;
    case 'dart-eval':
      return EngineType.dartEval;
  }
  return null;
}

String engineTypeToString(EngineType t) {
  switch (t) {
    case EngineType.ruleJson:
      return 'rule-json';
    case EngineType.scriptJs:
      return 'script-js';
    case EngineType.wasm:
      return 'wasm';
    case EngineType.dartEval:
      return 'dart-eval';
  }
}

class PackPermissions {
  const PackPermissions({
    required this.networkAllowList,
    this.cookieScopes = const [],
    this.storage = 'kv',
  });

  final List<String> networkAllowList;
  final List<String> cookieScopes;
  final String storage;

  factory PackPermissions.fromJson(Map<String, dynamic> j) {
    final allow = (j['networkAllowList'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final cookies = (j['cookieScopes'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final storage = (j['storage'] as String?) ?? 'kv';
    return PackPermissions(networkAllowList: allow, cookieScopes: cookies, storage: storage);
  }

  Map<String, dynamic> toJson() => {
        'networkAllowList': networkAllowList,
        'cookieScopes': cookieScopes,
        'storage': storage,
      };
}

class EngineManifest {
  const EngineManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.engineType,
    required this.entry,
    required this.permissions,
  });

  final String id;
  final String name;
  final String version;
  final EngineType engineType;
  final String entry;
  final PackPermissions permissions;

  factory EngineManifest.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as String?)?.trim() ?? '';
    final name = (j['name'] as String?)?.trim() ?? '';
    final version = (j['version'] as String?)?.trim() ?? '0.0.0';
    final engineTypeStr = (j['engineType'] as String?)?.trim() ?? '';
    final engineType = engineTypeFromString(engineTypeStr);
    final entry = (j['entry'] as String?)?.trim() ?? '';
    final perms = PackPermissions.fromJson((j['permissions'] as Map?)?.cast<String, dynamic>() ?? {});
    if (id.isEmpty || name.isEmpty || engineType == null || entry.isEmpty) {
      throw FormatException('Invalid manifest: missing required fields.');
    }
    if (perms.networkAllowList.isEmpty) {
      throw FormatException('Invalid manifest: permissions.networkAllowList is required.');
    }
    return EngineManifest(
      id: id,
      name: name,
      version: version,
      engineType: engineType,
      entry: entry,
      permissions: perms,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'engineType': engineTypeToString(engineType),
        'entry': entry,
        'permissions': permissions.toJson(),
      };
}

/// 已安装 Pack 的本地记录（不含大文件内容）
class InstalledPack {
  const InstalledPack({
    required this.manifest,
    required this.installedAtMs,
    required this.localPath,
    this.enabled = true,
  });

  final EngineManifest manifest;
  final int installedAtMs;
  final String localPath; // 解包后的目录 path
  final bool enabled;

  String get id => manifest.id;

  factory InstalledPack.fromJson(Map<String, dynamic> j) {
    return InstalledPack(
      manifest: EngineManifest.fromJson((j['manifest'] as Map).cast<String, dynamic>()),
      installedAtMs: (j['installedAtMs'] as int?) ?? 0,
      localPath: (j['localPath'] as String?) ?? '',
      enabled: (j['enabled'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'manifest': manifest.toJson(),
        'installedAtMs': installedAtMs,
        'localPath': localPath,
        'enabled': enabled,
      };
}

/// active source：要么是 ruleId，要么是 packId（先做 packId 即可）
sealed class ActiveSource {
  const ActiveSource();
  Map<String, dynamic> toJson();

  factory ActiveSource.fromJson(Map<String, dynamic> j) {
    final type = (j['type'] as String?) ?? '';
    if (type == 'pack') {
      return PackSource((j['packId'] as String?) ?? '');
    }
    if (type == 'rule') {
      return RuleSource((j['ruleId'] as String?) ?? '');
    }
    return const NoneSource();
  }
}

class NoneSource extends ActiveSource {
  const NoneSource();
  @override
  Map<String, dynamic> toJson() => {'type': 'none'};
}

class RuleSource extends ActiveSource {
  const RuleSource(this.ruleId);
  final String ruleId;
  @override
  Map<String, dynamic> toJson() => {'type': 'rule', 'ruleId': ruleId};
}

class PackSource extends ActiveSource {
  const PackSource(this.packId);
  final String packId;
  @override
  Map<String, dynamic> toJson() => {'type': 'pack', 'packId': packId};
}