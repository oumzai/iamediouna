import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// قارئ XLSX مبسط وموثوق: يقرأ النصوص والأرقام فقط من كل ورقة.
/// كُتب خصيصًا لملفات مسار (ورقة لكل قسم، سلاسل مشتركة، خلايا مدمجة)،
/// ويتحمل اختلافات الصيغة (BOM، بادئات الأسماء، النصوص المضمنة).
class XlsxSheet {
  final String name;
  final Map<int, Map<int, String>> _rows;

  XlsxSheet(this.name, this._rows);

  /// قيمة الخلية (الصف والعمود يبدآن من 1). تُرجع نصًا فارغًا إذا لم توجد.
  String cell(int row, int col) => _rows[row]?[col] ?? '';

  List<int> get rowNumbers => _rows.keys.toList()..sort();

  int get maxRow => _rows.isEmpty ? 0 : _rows.keys.reduce((a, b) => a > b ? a : b);

  /// خلايا الصف غير الفارغة مرتبة حسب العمود.
  List<MapEntry<int, String>> rowCells(int row) {
    final r = _rows[row];
    if (r == null) return const [];
    final list = r.entries.where((e) => e.value.trim().isNotEmpty).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return list;
  }
}

class XlsxWorkbook {
  final List<XlsxSheet> sheets;
  XlsxWorkbook(this.sheets);

  static XlsxWorkbook decode(Uint8List bytes) {
    final archive = _unzip(bytes);

    XmlDocument? readXml(String path) {
      final f = archive.findFile(path);
      if (f == null) return null;
      var text = utf8.decode(f.content, allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      return XmlDocument.parse(text);
    }

    final wbDoc = readXml('xl/workbook.xml');
    if (wbDoc == null) throw const FormatException('بنية ملف Excel غير معروفة.');

    // العلاقات: rId → مسار الورقة
    final rels = <String, String>{};
    final relDoc = readXml('xl/_rels/workbook.xml.rels');
    if (relDoc != null) {
      for (final r in _all(relDoc, 'Relationship')) {
        final id = _attr(r, 'Id');
        var target = _attr(r, 'Target');
        if (id == null || target == null) continue;
        if (target.startsWith('/')) {
          target = target.substring(1);
        } else if (!target.startsWith('xl/')) {
          target = 'xl/$target';
        }
        rels[id] = target;
      }
    }

    // السلاسل المشتركة
    final shared = <String>[];
    final ssDoc = readXml('xl/sharedStrings.xml');
    if (ssDoc != null) {
      for (final si in _all(ssDoc, 'si')) {
        shared.add(_stringItemText(si));
      }
    }

    final sheets = <XlsxSheet>[];
    var index = 0;
    for (final s in _all(wbDoc, 'sheet')) {
      index++;
      final name = _attr(s, 'name') ?? 'Sheet$index';
      String? rid;
      for (final a in s.attributes) {
        if (a.name.local == 'id' && a.name.prefix != null) rid = a.value;
      }
      final path = (rid != null ? rels[rid] : null) ?? 'xl/worksheets/sheet$index.xml';
      final doc = readXml(path);
      if (doc == null) continue;
      sheets.add(XlsxSheet(name, _readSheet(doc, shared)));
    }
    return XlsxWorkbook(sheets);
  }

  static Archive _unzip(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('الملف ليس ملف Excel صالحًا (xlsx).');
    }
  }

  static Map<int, Map<int, String>> _readSheet(XmlDocument doc, List<String> shared) {
    final rows = <int, Map<int, String>>{};
    var rowCounter = 0;
    for (final row in _all(doc, 'row')) {
      rowCounter++;
      final rAttr = int.tryParse(_attr(row, 'r') ?? '');
      final rowNum = rAttr ?? rowCounter;
      rowCounter = rowNum;
      final cells = <int, String>{};
      var colCounter = 0;
      for (final c in _children(row, 'c')) {
        colCounter++;
        final ref = _attr(c, 'r');
        final col = ref != null ? _colIndex(ref) : colCounter;
        colCounter = col;
        final type = _attr(c, 't') ?? 'n';
        String value = '';
        if (type == 'inlineStr') {
          final isEl = _children(c, 'is');
          if (isEl.isNotEmpty) value = _stringItemText(isEl.first);
        } else {
          final v = _children(c, 'v');
          final raw = v.isEmpty ? '' : v.first.innerText;
          if (type == 's') {
            final i = int.tryParse(raw.trim());
            value = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
          } else if (type == 'n') {
            value = _formatNumber(raw);
          } else {
            value = raw;
          }
        }
        if (value.isNotEmpty) cells[col] = value;
      }
      if (cells.isNotEmpty) rows[rowNum] = cells;
    }
    return rows;
  }

  /// نص عنصر <si> أو <is> مع تجاهل النطق الصوتي <rPh>.
  static String _stringItemText(XmlElement si) {
    final sb = StringBuffer();
    void walk(XmlElement e) {
      for (final child in e.children.whereType<XmlElement>()) {
        final local = child.name.local;
        if (local == 'rPh' || local == 'phoneticPr') continue;
        if (local == 't') {
          sb.write(child.innerText);
        } else {
          walk(child);
        }
      }
    }

    walk(si);
    return sb.toString();
  }

  static String _formatNumber(String raw) {
    final t = raw.trim();
    final d = double.tryParse(t);
    if (d == null) return t;
    if (d == d.truncateToDouble() && d.abs() < 1e15) return d.toInt().toString();
    return t;
  }

  /// "AB12" ← 28
  static int _colIndex(String ref) {
    var n = 0;
    for (final ch in ref.toUpperCase().codeUnits) {
      if (ch >= 65 && ch <= 90) {
        n = n * 26 + (ch - 64);
      } else {
        break;
      }
    }
    return n == 0 ? 1 : n;
  }

  static Iterable<XmlElement> _all(XmlNode node, String local) =>
      node.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static List<XmlElement> _children(XmlElement e, String local) =>
      e.children.whereType<XmlElement>().where((c) => c.name.local == local).toList();

  static String? _attr(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local && a.name.prefix == null) return a.value;
    }
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }
}
