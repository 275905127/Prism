import '../storage/local_store.dart';
import '../plugin/pack_models.dart';

class PackStore {
  PackStore(this._store);

  final LocalStore _store;

  static const _file = 'packs.json';

  Future<(List<InstalledPack>, ActiveSource)> load() async {
    final j = await _store.readJson(_file);
    final packsJ = (j['installedPacks'] as List?)?.whereType<Map>().toList() ?? const [];
    final packs = packsJ
        .map((e) => InstalledPack.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);

    final activeJ = (j['activeSource'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final active = activeJ.isEmpty ? const NoneSource() : ActiveSource.fromJson(activeJ);

    return (packs, active);
  }

  Future<void> save(List<InstalledPack> packs, ActiveSource active) async {
    await _store.writeJson(_file, {
      'installedPacks': packs.map((e) => e.toJson()).toList(),
      'activeSource': active.toJson(),
    });
  }
}