import 'dart:async';

import 'package:flutter/material.dart';

import '../core/layout.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'book_screen.dart';

/// Every book saved on the phone, with the space each one takes and a way to remove it.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final Map<String, int> _sizes = {};

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<void> _measure() async {
    final downloads = AppScope.read(context).downloads;
    for (final book in downloads.books) {
      final id = book['id'].toString();
      final size = await downloads.sizeOf(id);
      if (!mounted) {
        return;
      }
      setState(() => _sizes[id] = size);
    }
  }

  static String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0);

  Future<void> _remove(Map<String, dynamic> book) async {
    final title = (book['title'] ?? '').toString();
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(dialog.t('remove_saved_title', {'title': title})),
        content: Text(dialog.t('remove_saved_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(dialog.t('keep'))),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text(dialog.t('remove'), style: TextStyle(color: Palette.bad))),
        ],
      ),
    );
    if (sure != true || !mounted) {
      return;
    }
    final id = book['id'].toString();
    await AppScope.read(context).downloads.remove(id);
    if (mounted) {
      setState(() => _sizes.remove(id));
      showMessage(context, context.t('removed_done'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = AppScope.of(context).downloads.books;
    final total = _sizes.values.fold<int>(0, (sum, size) => sum + size);
    final measured = _sizes.length == books.length;
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: ListView(
            padding: Layout.page(context, top: 8, bottom: 28),
            children: [
              Row(children: [RoundButton(icon: Icons.arrow_back_rounded, label: context.t('back'), onTap: () => Navigator.of(context).maybePop())]),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DisplayTitle(context.t('saved_a'), second: context.t('saved_b'), size: 30),
                    const SizedBox(height: 6),
                    Text(
                      books.isEmpty ? context.t('saved_none') : measured ? context.t('saved_space', {'mb': _megabytes(total)}) : context.t('saved_measuring'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (books.isNotEmpty)
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < books.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
                          leading: SizedBox(width: 34, child: BookCover(book: books[i], width: 34)),
                          title: Text((books[i]['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.ink)),
                          subtitle: Text(
                            _sizes[books[i]['id'].toString()] == null ? context.t('saved_measuring') : context.t('size_mb', {'mb': _megabytes(_sizes[books[i]['id'].toString()]!)}),
                            style: TextStyle(fontSize: 12, color: Palette.muted),
                          ),
                          trailing: TextButton(
                            onPressed: () => _remove(books[i]),
                            child: Text(context.t('remove'), style: TextStyle(color: Palette.bad, fontSize: 12.5)),
                          ),
                          onTap: () => openBook(context, books[i]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
