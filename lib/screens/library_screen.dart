import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/layout.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/book_tile.dart';
import '../widgets/ui.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.searchFocus});

  final FocusNode searchFocus;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _typing;
  List<Map<String, dynamic>> _subjects = const [];
  List<Map<String, dynamic>> _authors = const [];
  List<Map<String, dynamic>> _books = [];
  String _subject = '';
  String _author = '';
  int _page = 1;
  int _count = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFilters());
    unawaited(_search());
  }

  @override
  void dispose() {
    _typing?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    final cache = AppScope.read(context).cache;
    try {
      List<Map<String, dynamic>> rows(Map<String, dynamic> data) => [for (final row in (data['results'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
      final results = await Future.wait([
        cache.load('subjects', onUpdate: (data) {
          if (mounted) {
            setState(() => _subjects = rows(data));
          }
        }),
        cache.load('authors', onUpdate: (data) {
          if (mounted) {
            setState(() => _authors = rows(data));
          }
        }),
      ]);
      if (mounted) {
        setState(() {
          _subjects = rows(results[0]);
          _authors = rows(results[1]);
        });
      }
    } on ApiException {
      return;
    }
  }

  Future<void> _search({bool more = false}) async {
    final request = ++_request;
    final page = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    final query = <String, String>{
      'page': '$page',
      if (_subject.isNotEmpty) 'subject': _subject,
      if (_author.isNotEmpty) 'author': _author,
      if (_query.text.trim().isNotEmpty) 'q': _query.text.trim(),
    };
    void show(Map<String, dynamic> data) {
      if (!mounted || request != _request) {
        return;
      }
      final rows = [for (final row in (data['results'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
      setState(() {
        _books = more ? [..._books, ...rows] : rows;
        _page = page;
        _count = (data['count'] as num?)?.toInt() ?? _books.length;
        _hasMore = data['next'] != null;
        _loading = false;
      });
    }

    try {
      // The first page opens from the copy kept on the phone and refreshes quietly behind it.
      show(await AppScope.read(context).cache.load('books', query: query, onUpdate: more ? null : show));
    } on ApiException catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _typed(String _) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 400), _search);
  }

  void _pickSubject(String slug) {
    setState(() => _subject = _subject == slug ? '' : slug);
    unawaited(_search());
  }

  @override
  Widget build(BuildContext context) {
    return PullRefresh(
      onRefresh: _search,
      child: ListView(
        padding: Layout.page(context, top: 16, bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DisplayTitle(context.t('library_title'), second: _loading && _books.isEmpty ? '' : context.t('book_count', {'n': whole(_count)})),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _query,
            focusNode: widget.searchFocus,
            onChanged: _typed,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            maxLength: 100,
            decoration: InputDecoration(
              hintText: context.t('search_hint'),
              counterText: '',
              prefixIcon: Icon(Icons.search_rounded, size: 19, color: Palette.muted),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.t('clear'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _query.clear();
                        unawaited(_search());
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          if (_subjects.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final subject in _subjects)
                  ChoiceChip(
                    label: Text('${subject['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: _subject == subject['slug'],
                    onSelected: (_) => _pickSubject(subject['slug'].toString()),
                    showCheckmark: false,
                    labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _subject == subject['slug'] ? Colors.white : Palette.ink),
                    selectedColor: Palette.solid,
                    backgroundColor: Palette.surface,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          if (_authors.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _author,
              isExpanded: true,
              decoration: InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded, size: 19, color: Palette.muted)),
              items: [
                DropdownMenuItem(value: '', child: Text(context.t('all_scholars'))),
                for (final author in _authors)
                  DropdownMenuItem(value: author['slug'].toString(), child: Text('${author['name']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) {
                setState(() => _author = value ?? '');
                unawaited(_search());
              },
            ),
          ],
          const SizedBox(height: 14),
          if (_error != null && _books.isEmpty)
            LoadView(error: _error, onRetry: _search)
          else if (_loading && _books.isEmpty)
            const LoadView(skeleton: SkeletonGrid())
          else if (_books.isEmpty)
            Panel(child: Text(context.t('no_match'), textAlign: TextAlign.center))
          else ...[
            AdaptiveGrid(minTileWidth: 150, spacing: 8, children: [for (final book in _books) BookTile(book: book)]),
            if (_hasMore) ...[
              const SizedBox(height: 14),
              BusyButton(label: context.t('show_more'), style: BusyStyle.light, onPressed: () => _search(more: true)),
            ],
          ],
        ],
      ),
    );
  }
}
