import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../core/api.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import 'ui.dart';

/// The page on the website that shows a chapter, opened from the link in the WhatsApp message.
String chapterLink(String chapterId, {Object? paragraph}) => '${AppConfig.apiBase}/read/$chapterId/${paragraph == null ? '' : '#p$paragraph'}';

/// Lets the reader pick a scholar, write a question and send it on WhatsApp with the passage and its link.
Future<void> askScholar(BuildContext context, {required String reference, required String link}) async {
  final scholar = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: Palette.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ScholarPicker(),
  );
  if (scholar == null || !context.mounted) {
    return;
  }
  final question = await showDialog<String>(context: context, builder: (_) => _QuestionDialog(scholar: scholar));
  if (question == null || question.isEmpty || !context.mounted) {
    return;
  }
  final text = '${context.t('question_on_this', {'question': question})}\n\n$reference\n$link';
  final uri = Uri.parse('https://wa.me/${scholar['whatsapp']}?text=${Uri.encodeComponent(text)}');
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException {
    opened = false;
  }
  if (!opened && context.mounted) {
    showMessage(context, context.t('whatsapp_missing'));
  }
}

const _fields = ['fiqh', 'hadith', 'aqeedah', 'tafsir', 'seerah', 'tazkiyah', 'arabic', 'general'];
final _digits = RegExp(r'^[1-9]\d{9,14}$');

class _ScholarPicker extends StatefulWidget {
  const _ScholarPicker();

  @override
  State<_ScholarPicker> createState() => _ScholarPickerState();
}

class _ScholarPickerState extends State<_ScholarPicker> {
  static const _page = 8;

  List<Map<String, dynamic>>? _all;
  Object? _error;
  String _query = '';
  String _field = '';
  int _shown = _page;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await AppScope.read(context).api.get('scholars');
      if (mounted) {
        setState(() => _all = [
          for (final row in (data as List))
            if (_digits.hasMatch((row as Map)['whatsapp']?.toString() ?? '')) Map<String, dynamic>.from(row),
        ]);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final query = _query.trim().toLowerCase();
    final matches = all == null
        ? const <Map<String, dynamic>>[]
        : [
            for (final s in all)
              if ((_field.isEmpty || s['field'] == _field) && (query.isEmpty || s['name'].toString().toLowerCase().contains(query))) s,
          ];
    final fields = all == null ? const <String>[] : [for (final f in _fields) if (all.any((s) => s['field'] == f)) f];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.t('ask_scholar'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                if (all == null)
                  LoadView(error: _error, onRetry: _load)
                else if (all.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(context.t('scholars_none'), textAlign: TextAlign.center))
                else ...[
                  TextField(
                    decoration: InputDecoration(hintText: context.t('search_scholars'), prefixIcon: const Icon(Icons.search_rounded, size: 20), isDense: true),
                    onChanged: (value) => setState(() {
                      _query = value;
                      _shown = _page;
                    }),
                  ),
                  if (fields.length > 1) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in ['', ...fields])
                          ChoiceChip(
                            label: Text(f.isEmpty ? context.t('all') : context.t('field_$f'), style: const TextStyle(fontSize: 12.5)),
                            selected: _field == f,
                            showCheckmark: false,
                            selectedColor: Palette.greenSoft,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() {
                              _field = f;
                              _shown = _page;
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (matches.isEmpty)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(context.t('no_scholars'), textAlign: TextAlign.center))
                  else
                    for (final s in matches.take(_shown))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ScholarFace(scholar: s),
                        title: Text(s['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: Palette.ink)),
                        subtitle: Text(context.t('field_${s['field']}'), style: Theme.of(context).textTheme.bodySmall),
                        onTap: () => Navigator.of(context).pop(s),
                      ),
                  if (matches.length > _shown)
                    TextButton(onPressed: () => setState(() => _shown += _page), child: Text(context.t('more'), style: TextStyle(color: Palette.green))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small round photo, or the first letter of the name when there is no photo.
class ScholarFace extends StatelessWidget {
  const ScholarFace({super.key, required this.scholar, this.radius = 20});

  final Map<String, dynamic> scholar;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = (scholar['photo'] ?? '').toString();
    final name = scholar['name'].toString().trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Palette.greenSoft,
      foregroundImage: photo.startsWith('https://') ? NetworkImage(photo) : null,
      child: Text(name.isEmpty ? '' : name.characters.first.toUpperCase(), style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600, color: Palette.greenDeep)),
    );
  }
}

class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({required this.scholar});

  final Map<String, dynamic> scholar;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  final TextEditingController _question = TextEditingController();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.surface,
      title: Row(
        children: [
          ScholarFace(scholar: widget.scholar, radius: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.scholar['name'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: Palette.ink))),
        ],
      ),
      content: TextField(
        controller: _question,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        maxLength: 500,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: context.t('your_question')),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.t('cancel'), style: TextStyle(color: Palette.muted))),
        TextButton(
          onPressed: _question.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_question.text.trim()),
          child: Text(context.t('send_whatsapp'), style: TextStyle(color: _question.text.trim().isEmpty ? Palette.muted : Palette.green, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
