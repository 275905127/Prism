import 'package:flutter/foundation.dart';
import '../plugin/pack_models.dart';
import '../storage/local_store.dart';
import '../storage/pack_store.dart';

class SourceManager extends ChangeNotifier {
  SourceManager() {
    _init();
  }

  final LocalStore _localStore = LocalStore();
  late final PackStore _packStore = PackStore(_localStore);

  List<InstalledPack> _packs = const [];
  ActiveSource _activeSource = const NoneSource();

  List<InstalledPack> get installedPacks => _packs;
  ActiveSource get activeSource => _activeSource;

  InstalledPack? get activePack {
    if (_activeSource is! PackSource) return null;
    final id = (_activeSource as PackSource).packId;
    return _packs.where((p) => p.id == id).cast<InstalledPack?>().firstWhere((e) => e != null, orElse: () => null);
  }

  Future<void> _init() async {
    try {
      final (packs, active) = await _packStore.load();
      _packs = packs;
      _activeSource = active;
    } catch (e) {
      // 这里建议接入你自己的 logger
      _packs = const [];
      _activeSource = const NoneSource();
    }
    notifyListeners();
  }

  Future<void> setActivePack(String packId) async {
    _activeSource = PackSource(packId);
    await _packStore.save(_packs, _activeSource);
    notifyListeners();
  }

  Future<void> upsertPack(InstalledPack pack) async {
    final idx = _packs.indexWhere((p) => p.id == pack.id);
    final next = [..._packs];
    if (idx >= 0) {
      next[idx] = pack;
    } else {
      next.add(pack);
    }
    _packs = next;
    await _packStore.save(_packs, _activeSource);
    notifyListeners();
  }

  Future<void> setPackEnabled(String packId, bool enabled) async {
    _packs = _packs
        .map((p) => p.id == packId ? InstalledPack(manifest: p.manifest, installedAtMs: p.installedAtMs, localPath: p.localPath, enabled: enabled) : p)
        .toList(growable: false);
    await _packStore.save(_packs, _activeSource);
    notifyListeners();
  }
}