import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../data/db.dart';

/// أدوات عرض صفحات PDF (للأستاذ فقط) واختيار صفحة كصورة.
class PdfTools {
  PdfTools._();

  static Future<Uint8List?> readStoryPdf(String? relPath) async {
    if (relPath == null) return null;
    final f = AppDb.I.file(relPath);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  /// صورة PNG لصفحة واحدة (تُستعمل كغلاف افتراضي أو كصورة سؤال).
  static Future<Uint8List?> renderPage(Uint8List pdf, int page, {double dpi = 110}) async {
    try {
      await for (final r in Printing.raster(pdf, pages: [page], dpi: dpi)) {
        return await r.toPng();
      }
    } catch (_) {}
    return null;
  }
}

/// نافذة تعرض صفحات القصة مصغرة؛ عند الاختيار تُرجع صورة الصفحة بدقة أعلى.
class PdfPagePicker extends StatefulWidget {
  final Uint8List pdf;
  final bool pickMode;
  const PdfPagePicker({super.key, required this.pdf, this.pickMode = true});

  static Future<Uint8List?> pick(BuildContext context, Uint8List pdf) => Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => PdfPagePicker(pdf: pdf)),
      );

  @override
  State<PdfPagePicker> createState() => _PdfPagePickerState();
}

class _PdfPagePickerState extends State<PdfPagePicker> {
  final pages = <Uint8List>[];
  bool done = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    try {
      await for (final r in Printing.raster(widget.pdf, dpi: widget.pickMode ? 45 : 90)) {
        final png = await r.toPng();
        if (!mounted) return;
        setState(() => pages.add(png));
      }
    } catch (e) {
      error = 'تعذر عرض ملف PDF: $e';
    }
    if (mounted) setState(() => done = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.pickMode ? 'اختر صفحة من القصة' : 'صفحات القصة (للأستاذ)')),
      body: error != null
          ? Center(child: Text(error!))
          : pages.isEmpty && !done
              ? const Center(child: CircularProgressIndicator())
              : widget.pickMode
                  ? GridView.extent(
                      maxCrossAxisExtent: 180,
                      padding: const EdgeInsets.all(10),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.72,
                      children: [
                        for (var i = 0; i < pages.length; i++)
                          InkWell(
                            onTap: () async {
                              final hi = await PdfTools.renderPage(widget.pdf, i);
                              if (context.mounted) Navigator.pop(context, hi ?? pages[i]);
                            },
                            child: Column(children: [
                              Expanded(child: Image.memory(pages[i], fit: BoxFit.contain)),
                              Text('صفحة ${i + 1}'),
                            ]),
                          ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: pages.length,
                      itemBuilder: (c, i) => Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(children: [
                          InteractiveViewer(child: Image.memory(pages[i], fit: BoxFit.contain)),
                          Text('صفحة ${i + 1}'),
                        ]),
                      ),
                    ),
    );
  }
}
