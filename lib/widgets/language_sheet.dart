import 'package:flutter/material.dart';

import '../core/prefs.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import 'ui.dart';

/// Lets the reader pick the app's look and language. Each language is written in itself so anyone can find theirs.
Future<void> pickLanguage(BuildContext context) {
  final prefs = AppScope.read(context).prefs;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.surface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sheet.t('app_look'), style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListenableBuilder(
                listenable: prefs,
                builder: (_, _) => Segmented<AppLook>(
                  height: 34,
                  options: [(AppLook.phone, sheet.t('look_phone')), (AppLook.light, sheet.t('look_light')), (AppLook.dark, sheet.t('look_dark'))],
                  value: prefs.look,
                  onChanged: prefs.setLook,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(sheet.t('app_language'), style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final code in Strings.names.keys)
              ListTile(
                title: Text(Strings.names[code]!, style: TextStyle(fontSize: 15, color: Palette.ink)),
                trailing: prefs.language == code ? Icon(Icons.check_rounded, color: Palette.green, size: 20) : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () {
                  prefs.setLanguage(code);
                  Navigator.of(sheet).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}
