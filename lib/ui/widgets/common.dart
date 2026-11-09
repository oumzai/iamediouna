import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/db.dart';

// ---------------- رسائل وتأكيدات ----------------

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontSize: 16)),
    backgroundColor: error ? AppColors.danger : AppColors.primaryDark,
    duration: Duration(seconds: error ? 5 : 3),
  ));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'تأكيد', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        ElevatedButton(
          style: danger ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

Future<void> info(BuildContext context, String title, Widget content) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: content),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(c), child: const Text('حسنًا'))],
      ),
    );

/// تنفيذ عملية طويلة مع نافذة انتظار، وعرض الخطأ بوضوح إن حدث.
Future<T?> withProgress<T>(BuildContext context, String message, Future<T> Function() task) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 16))),
        ]),
      ),
    ),
  );
  try {
    final r = await task();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return r;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      toast(context, errorText(e), error: true);
    }
    return null;
  }
}

String errorText(Object e) {
  final s = e.toString();
  for (final p in ['Exception: ', 'FormatException: ', 'Bad state: ', 'StateError: ']) {
    if (s.startsWith(p)) return s.substring(p.length);
  }
  return s;
}

/// نافذة إدخال كلمة سر.
Future<String?> askPassword(BuildContext context, String title, {String label = 'كلمة السر', bool numeric = false}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        obscureText: true,
        autofocus: true,
        keyboardType: numeric ? TextInputType.number : TextInputType.visiblePassword,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('دخول')),
      ],
    ),
  );
}

Future<String?> askText(BuildContext context, String title,
    {String label = '', String initial = '', int maxLines = 1, TextInputType? keyboard}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('حفظ')),
      ],
    ),
  );
}

// ---------------- عناصر الواجهة ----------------

class BigTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;
  final double height;

  const BigTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.color = AppColors.primary,
    this.onTap,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(24),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: height * 0.36, color: Colors.white),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                if (subtitle != null)
                  Text(subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;
  const StatCard({super.key, required this.title, required this.value, required this.icon,
      this.color = AppColors.primary, this.hint});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
                Text(title, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                if (hint != null) Text(hint!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 72, color: AppColors.muted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: AppColors.muted)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// صورة من ملفات التطبيق (مسار نسبي) مع بديل عند غيابها.
class LocalImage extends StatelessWidget {
  final String? path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  const LocalImage(this.path, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.placeholder});

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null || p.isEmpty) return placeholder ?? SizedBox(width: width, height: height);
    final f = File(AppDb.I.abs(p));
    return Image.file(f, width: width, height: height, fit: fit,
        errorBuilder: (c, e, s) => placeholder ?? SizedBox(width: width, height: height, child: const Icon(Icons.broken_image)));
  }
}

/// غلاف القصة: الصورة إن وجدت، وإلا بطاقة ملونة بالعنوان.
class StoryCover extends StatelessWidget {
  final String? coverPath;
  final String title;
  final double width;
  final double height;
  const StoryCover({super.key, this.coverPath, required this.title, this.width = 150, this.height = 200});

  static const _palette = [
    Color(0xFF1F7A6D), Color(0xFF2F5D8A), Color(0xFFE07A3F), Color(0xFF8E5AA8), Color(0xFFB8860B), Color(0xFF3C8D5C),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[title.hashCode.abs() % _palette.length];
    final ph = Container(
      width: width,
      height: height,
      color: color,
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.menu_book, color: Colors.white, size: 40),
        const SizedBox(height: 8),
        Text(title,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: LocalImage(coverPath, width: width, height: height, placeholder: ph),
    );
  }
}

/// رسم أعمدة بسيط (دون مكتبات خارجية).
class SimpleBars extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final double maxValue;
  final Color color;
  final String Function(double)? valueText;
  final double height;
  const SimpleBars({super.key, required this.labels, required this.values, this.maxValue = 0,
      this.color = AppColors.primary, this.valueText, this.height = 160});

  @override
  Widget build(BuildContext context) {
    final mx = maxValue > 0 ? maxValue : (values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b));
    final safeMax = mx <= 0 ? 1.0 : mx;
    return SizedBox(
      height: height + 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final double h = (values[i] / safeMax).clamp(0.0, 1.0).toDouble() * height;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(valueText != null ? valueText!(values[i]) : values[i].round().toString(),
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                const SizedBox(height: 2),
                Container(
                  height: h < 2 ? 2 : h,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                ),
                const SizedBox(height: 4),
                Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

/// عنصر تنقل في الواجهات الإدارية.
class NavItem {
  final IconData icon;
  final String label;
  final WidgetBuilder builder;
  final int? badge;
  const NavItem(this.icon, this.label, this.builder, {this.badge});
}

/// هيكل متجاوب: شريط جانبي على التابلت، وقائمة منسدلة على الهاتف.
class NavShell extends StatefulWidget {
  final String title;
  final Color color;
  final List<NavItem> items;
  final List<Widget> actions;
  final Widget? header;
  const NavShell({super.key, required this.title, required this.items, this.color = AppColors.primary,
      this.actions = const [], this.header});

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 840;
    final item = widget.items[index];
    final body = KeyedSubtree(key: ValueKey(index), child: item.builder(context));
    Widget icon(NavItem it) => it.badge != null && it.badge! > 0
        ? Badge(label: Text('${it.badge}'), child: Icon(it.icon))
        : Icon(it.icon);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.color,
        title: Text(wide ? widget.title : '${widget.title} — ${item.label}'),
        actions: widget.actions,
      ),
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(children: [
                  if (widget.header != null) widget.header!,
                  for (var i = 0; i < widget.items.length; i++)
                    ListTile(
                      leading: icon(widget.items[i]),
                      title: Text(widget.items[i].label, style: const TextStyle(fontSize: 17)),
                      selected: i == index,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => index = i);
                      },
                    ),
                ]),
              ),
            ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => index = i),
                labelType: NavigationRailLabelType.all,
                leading: widget.header,
                destinations: [
                  for (final it in widget.items)
                    NavigationRailDestination(icon: icon(it), label: Text(it.label, textAlign: TextAlign.center)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
    );
  }
}

/// لوحة أرقام كبيرة لإدخال رمز التلميذ.
class PinPad extends StatefulWidget {
  final int length;
  final ValueChanged<String> onDone;
  const PinPad({super.key, this.length = 4, required this.onDone});

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String value = '';

  void clear() => setState(() => value = '');

  void _tap(String d) {
    if (value.length >= widget.length) return;
    setState(() => value += d);
    if (value.length == widget.length) widget.onDone(value);
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 84,
            height: 76,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primaryDark,
                elevation: 2,
                padding: EdgeInsets.zero,
              ),
              onPressed: onTap ?? () => _tap(label),
              child: icon != null ? Icon(icon, size: 30) : Text(label, style: const TextStyle(fontSize: 32)),
            ),
          ),
        );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.length, (i) {
            final filled = i < value.length;
            return Container(
              margin: const EdgeInsets.all(8),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppColors.student : Colors.transparent,
                border: Border.all(color: AppColors.student, width: 3),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          key('', icon: Icons.backspace_outlined, onTap: () {
            if (value.isNotEmpty) setState(() => value = value.substring(0, value.length - 1));
          }),
          key('0'),
          key('', icon: Icons.clear, onTap: clear),
        ]),
      ]),
    );
  }
}
