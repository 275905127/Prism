import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalStore {
  LocalStore({this.dirName = 'prism'});
  final String dirName;

  Future<Directory> _baseDir() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory('${doc.path}/$dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _file(String filename) async {
    final dir = await _baseDir();
    return File('${dir.path}/$filename');
  }

  Future<Map<String, dynamic>> readJson(String filename) async {
    final f = await _file(filename);
    if (!await f.exists()) return <String, dynamic>{};
    final raw = await f.readAsString();
    if (raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  Future<void> writeJson(String filename, Map<String, dynamic> data) async {
    final f = await _file(filename);
    final raw = const JsonEncoder.withIndent('  ').convert(data);
    await f.writeAsString(raw, flush: true);
  }

  Future<void> delete(String filename) async {
    final f = await _file(filename);
    if (await f.exists()) await f.delete();
  }
}