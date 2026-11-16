import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/biometric.dart';
import '../core/layout.dart';
import '../core/scope.dart';
import '../core/shield.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/language_sheet.dart';
import '../widgets/ui.dart';
import 'auth_screens.dart';
import 'reader_screen.dart';

Future<void> openAccount(BuildContext context) async {
  final signedIn = AppScope.read(context).session.signedIn;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => signedIn ? const AccountScreen() : const SignInScreen()));
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _name = TextEditingController();
  List<Map<String, dynamic>>? _progress;
  List<Map<String, dynamic>>? _bookmarks;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    final session = AppScope.read(context).session;
    _name.text = (session.profile?['display_name'] ?? '').toString();
    unawaited(_load());
    Biometric.available().then((value) {
      if (mounted) {
        setState(() => _biometricAvailable = value);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = AppScope.read(context);
    try {
      final results = await Future.wait([services.api.get('me', auth: true), services.api.get('progress', auth: true), services.api.get('bookmarks', auth: true)]);
      if (!mounted) {
        return;
      }
      services.session.setProfile(Map<String, dynamic>.from(results[0] as Map));
      setState(() {
        if (_name.text.isEmpty) {
          _name.text = (services.session.profile?['display_name'] ?? '').toString();
        }
        _progress = [for (final row in results[1] as List) Map<String, dynamic>.from(row as Map)];
        _bookmarks = [for (final row in results[2] as List) Map<String, dynamic>.from(row as Map)];
      });
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  Future<void> _saveName() async {
    final services = AppScope.read(context);
    try {
      services.session.setProfile(Map<String, dynamic>.from(await services.api.patch('me', body: {'display_name': _name.text.trim()}, auth: true) as Map));
      if (mounted) {
        showMessage(context, context.t('saved'));
      }
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  Future<void> _deleteBookmark(String id) async {
    try {
      await AppScope.read(context).api.delete('bookmarks/$id', auth: true);
      setState(() => _bookmarks?.removeWhere((row) => row['id'] == id));
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final session = AppScope.read(context).session;
    if (!value) {
      await session.setBiometric(false);
      return;
    }
    if (await Biometric.confirm(context.t('confirm_it_is_you'))) {
      await session.setBiometric(true);
    }
  }

  Future<void> _signOut({bool everywhere = false}) async {
    final services = AppScope.read(context);
    if (everywhere) {
      try {
        await services.api.post('auth/sign-out-everywhere', auth: true);
      } on ApiException catch (error) {
        if (mounted) {
          showMessage(context, context.describe(error));
        }
        return;
      }
    }
    await services.session.signOut(services.api);
    services.dhikr.forgetAccount();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _close() async {
    final closed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CloseAccountScreen()));
    if (closed == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _open(Map<String, dynamic> row) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(chapterId: row['chapter'].toString(), bookTitle: row['book_title'].toString())));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final session = services.session;
    final email = (session.profile?['email'] ?? '').toString();
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: PullRefresh(
            onRefresh: _load,
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
                      DisplayTitle(context.t('account_a'), second: context.t('account_b'), size: 30),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(context.t('signed_in_as', {'email': email}), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Field(label: context.t('display_name'), controller: _name, maxLength: 40),
                      BusyButton(label: context.t('save'), style: BusyStyle.light, onPressed: _saveName),
                      const Divider(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.t('app_language'), style: const TextStyle(fontSize: 14)),
                        trailing: Text(Strings.names[services.prefs.language]!, style: TextStyle(color: Palette.muted)),
                        onTap: () => pickLanguage(context),
                      ),
                      if (_biometricAvailable)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeTrackColor: Palette.green,
                          value: session.biometricEnabled,
                          title: Text(context.t('quick_unlock'), style: const TextStyle(fontSize: 14)),
                          onChanged: _toggleBiometric,
                        ),
                    ],
                  ),
                ),
                _Section(title: context.t('your_reading')),
                if (_progress == null)
                  const LoadView()
                else if (_progress!.isEmpty)
                  Panel(child: Text(context.t('no_reading'), textAlign: TextAlign.center))
                else
                  _Rows(rows: [for (final row in _progress!) (row['book_title'].toString(), row['chapter_title'].toString(), () => _open(row), null)]),
                _Section(title: context.t('bookmarks')),
                if (_bookmarks == null)
                  const LoadView()
                else if (_bookmarks!.isEmpty)
                  Panel(child: Text(context.t('no_bookmarks'), textAlign: TextAlign.center))
                else
                  _Rows(
                    rows: [
                      for (final row in _bookmarks!)
                        (
                          row['book_title'].toString(),
                          '${row['chapter_title']}  |  ${context.t('paragraph_n', {'n': row['paragraph_number'] ?? ''})}',
                          () => _open(row),
                          () => _deleteBookmark(row['id'].toString()),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                BusyButton(label: context.t('sign_out'), onPressed: _signOut),
                const SizedBox(height: 8),
                BusyButton(label: context.t('sign_out_all'), style: BusyStyle.light, onPressed: () => _signOut(everywhere: true)),
                const SizedBox(height: 8),
                TextButton(onPressed: _close, child: Text(context.t('close_account'), style: TextStyle(color: Palette.bad))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.fromLTRB(8, 22, 8, 8), child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.headlineSmall));
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows});

  final List<(String, String, VoidCallback, VoidCallback?)> rows;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(indent: 14, endIndent: 14),
            ListTile(
              dense: true,
              title: Text(rows[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Palette.ink)),
              subtitle: Text(rows[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: rows[i].$3,
              trailing: rows[i].$4 == null
                  ? const Icon(Icons.chevron_right_rounded, size: 20)
                  : IconButton(tooltip: context.t('delete'), icon: Icon(Icons.delete_outline_rounded, size: 19, color: Palette.muted), onPressed: rows[i].$4),
            ),
          ],
        ],
      ),
    );
  }
}

/// Both stores require that readers can close their account inside the app.
class CloseAccountScreen extends StatefulWidget {
  const CloseAccountScreen({super.key});

  @override
  State<CloseAccountScreen> createState() => _CloseAccountScreenState();
}

class _CloseAccountScreenState extends State<CloseAccountScreen> {
  final _password = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(Shield.protectScreen(true));
  }

  @override
  void dispose() {
    unawaited(Shield.protectScreen(false));
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final services = AppScope.read(context);
    setState(() => _error = null);
    try {
      await services.api.post('me/close', body: {'password': _password.text}, auth: true);
      await services.session.clear();
      services.dhikr.forgetAccount();
      if (mounted) {
        showMessage(context, context.t('account_closed'));
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.fields['password'] ?? context.describe(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      first: context.t('close_account'),
      second: '',
      children: [
        Text(context.t('close_account_body'), textAlign: TextAlign.justify),
        const SizedBox(height: 14),
        ErrorNote(_error),
        Field(label: context.t('password'), controller: _password, obscure: true, maxLength: 128, hints: const [AutofillHints.password]),
        BusyButton(label: context.t('close_account'), onPressed: _submit),
      ],
    );
  }
}
