import 'package:flutter/material.dart';

import '../screens/book_screen.dart';
import '../theme.dart';
import 'ui.dart';

/// Grid card for one book, used on Home and in the Library.
class BookTile extends StatelessWidget {
  const BookTile({super.key, required this.book, this.tag = ''});

  final Map<String, dynamic> book;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openBook(context, book),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 92,
                width: double.infinity,
                decoration: BoxDecoration(color: Palette.stone, borderRadius: BorderRadius.circular(14)),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    BookCover(book: book, width: 45),
                    if (tag.isNotEmpty) Positioned(top: 6, left: 6, child: Tag(tag)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 7, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((book['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Palette.ink)),
                    const SizedBox(height: 1),
                    Text((book['author'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Palette.muted)),
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
