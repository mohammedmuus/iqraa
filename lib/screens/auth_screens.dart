import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api.dart';
import '../core/biometric.dart';
import '../core/integrity.dart';
import '../core/layout.dart';
import '../core/scope.dart';
import '../core/shield.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'dhikr_screen.dart';

Future<void> openSignIn(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignInScreen()));
}

Future<Map<String, String>> _device() async {
  final info = await PackageInfo.fromPlatform();
  return {'platform': Platform.isIOS ? 'ios' : 'android', 'app_version': info.version, 'device_name': ''};
}

/// Saves the tokens, brings the dhikr counts across and offers fingerprint or face unlock the first time.
Future<void> completeSignIn(BuildContext context, Map data) async {
  final services = AppScope.read(context);
  await services.session.saveTokens(Map<String, dynamic>.from(data));
  final user = data['user'];
  services.session.setProfile(user is Map ? Map<String, dynamic>.from(user) : null);
  if (user is Map && user['email'] != null) {
    await services.session.rememberEmail(user['email'].toString());
  }
  unawaited(services.dhikr.sync());
  final navigator = services.navigatorKey.currentState;
  navigator?.popUntil((route) => route.isFirst);
  final invite = services.pendingInvite;
  if (invite != null && navigator != null) {
    services.pendingInvite = null;
    unawaited(joinGroup(navigator, services, invite));
  }
  final root = services.navigatorKey.currentContext;
  if (root == null || services.session.biometricEnabled || !await Biometric.available() || !root.mounted) {
    return;
  }
  final enable = await showDialog<bool>(
    context: root,
    builder: (dialog) => AlertDialog(
      title: Text(dialog.t('quick_unlock')),
      content: Text(dialog.t('quick_unlock_ask')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(dialog.t('not_now'))),
        TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text(dialog.t('turn_on'))),
      ],
    ),
  );
  if (enable == true && root.mounted && await Biometric.confirm(root.t('confirm_it_is_you'))) {
    await services.session.setBiometric(true);
  }
}

class Field extends StatelessWidget {
  const Field({super.key, required this.label, required this.controller, this.error, this.obscure = false, this.keyboard, this.hints, this.help, this.maxLength = 254});

  final String label;
  final TextEditingController controller;
  final String? error;
  final bool obscure;
  final TextInputType? keyboard;
  final Iterable<String>? hints;
  final String? help;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: Palette.muted)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboard,
            autofillHints: hints,
            maxLength: maxLength,
            enableSuggestions: !obscure,
            autocorrect: false,
            decoration: InputDecoration(errorText: error, errorMaxLines: 3, helperText: help, helperMaxLines: 2, counterText: ''),
          ),
        ],
      ),
    );
  }
}

/// Page frame for the account screens: back button, two tone heading, white card.
class AuthFrame extends StatelessWidget {
  const AuthFrame({super.key, required this.first, required this.second, required this.children});

  final String first;
  final String second;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: ListView(
            padding: Layout.page(context, top: 8, bottom: 28),
            children: [
              Row(children: [RoundButton(icon: Icons.arrow_back_rounded, label: context.t('back'), onTap: () => Navigator.of(context).maybePop())]),
              const SizedBox(height: 14),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: DisplayTitle(first, second: second, size: 30)),
              const SizedBox(height: 14),
              Panel(padding: const EdgeInsets.all(18), child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
            ],
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  String? _error;
  Map<String, String> _fields = const {};

  @override
  void initState() {
    super.initState();
    unawaited(Shield.protectScreen(true));
    AppScope.read(context).session.lastEmail().then((value) {
      if (value != null && mounted && _email.text.isEmpty) {
        _email.text = value;
      }
    });
  }

  @override
  void dispose() {
    unawaited(Shield.protectScreen(false));
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _fail(ApiException error) {
    setState(() {
      _error = error.fields.isEmpty ? context.describe(error) : null;
      _fields = error.fields;
    });
  }

  Future<void> _submit() async {
    final services = AppScope.read(context);
    final email = _email.text.trim().toLowerCase();
    setState(() {
      _error = null;
      _fields = const {};
    });
    try {
      final headers = await Integrity.headers(services.api);
      if (_register) {
        await services.api.post('auth/register', body: {'email': email, 'password': _password.text, 'display_name': _name.text.trim()}, headers: headers);
        if (mounted) {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VerifyScreen(email: email)));
        }
        return;
      }
      final data = await services.api.post('auth/sign-in', body: {'email': email, 'password': _password.text, ...await _device()}, headers: headers) as Map;
      if (mounted) {
        await completeSignIn(context, data);
      }
    } on ApiException catch (error) {
      if (mounted) {
        _fail(error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      first: context.t('account_a'),
      second: context.t('account_b'),
      children: [
        Segmented<bool>(
          height: 34,
          options: [(false, context.t('sign_in')), (true, context.t('register_tab'))],
          value: _register,
          onChanged: (value) => setState(() {
            _register = value;
            _error = null;
            _fields = const {};
          }),
        ),
        const SizedBox(height: 16),
        ErrorNote(_error),
        Field(label: context.t('email'), controller: _email, error: _fields['email'], keyboard: TextInputType.emailAddress, hints: const [AutofillHints.email]),
        Field(
          label: context.t('password'),
          controller: _password,
          error: _fields['password'],
          obscure: true,
          maxLength: 128,
          hints: [_register ? AutofillHints.newPassword : AutofillHints.password],
          help: _register ? context.t('password_rules') : null,
        ),
        if (_register) Field(label: context.t('display_name'), controller: _name, error: _fields['display_name'], maxLength: 40, hints: const [AutofillHints.name]),
        BusyButton(label: _register ? context.t('register_tab') : context.t('sign_in'), onPressed: _submit),
        if (!_register)
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ResetScreen(email: _email.text.trim()))),
            child: Text(context.t('forgot'), style: TextStyle(color: Palette.muted)),
          ),
      ],
    );
  }
}

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _code = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(Shield.protectScreen(true));
  }

  @override
  void dispose() {
    unawaited(Shield.protectScreen(false));
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final services = AppScope.read(context);
    setState(() => _error = null);
    try {
      final data = await services.api.post(
        'auth/verify',
        body: {'email': widget.email, 'code': _code.text.trim(), ...await _device()},
        headers: await Integrity.headers(services.api),
      ) as Map;
      if (mounted) {
        await completeSignIn(context, data);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = context.describe(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      first: context.t('account_a'),
      second: context.t('account_b'),
      children: [
        Text(context.t('code_sent_to', {'email': widget.email})),
        const SizedBox(height: 14),
        ErrorNote(_error),
        Field(label: context.t('code'), controller: _code, keyboard: TextInputType.number, maxLength: 6, hints: const [AutofillHints.oneTimeCode]),
        BusyButton(label: context.t('confirm'), onPressed: _submit),
      ],
    );
  }
}

class ResetScreen extends StatefulWidget {
  const ResetScreen({super.key, this.email = ''});

  final String email;

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  String? _error;
  Map<String, String> _fields = const {};

  @override
  void initState() {
    super.initState();
    unawaited(Shield.protectScreen(true));
  }

  @override
  void dispose() {
    unawaited(Shield.protectScreen(false));
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final api = AppScope.read(context).api;
    setState(() {
      _error = null;
      _fields = const {};
    });
    try {
      if (!_sent) {
        await api.post('auth/password/forgot', body: {'email': _email.text.trim().toLowerCase()});
        if (mounted) {
          setState(() => _sent = true);
        }
        return;
      }
      await api.post('auth/password/reset', body: {'email': _email.text.trim().toLowerCase(), 'code': _code.text.trim(), 'password': _password.text});
      if (mounted) {
        showMessage(context, context.t('password_changed'));
        Navigator.of(context).pop();
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.fields.isEmpty ? context.describe(error) : null;
          _fields = error.fields;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      first: context.t('reset_title'),
      second: '',
      children: [
        ErrorNote(_error),
        Field(label: context.t('email'), controller: _email, error: _fields['email'], keyboard: TextInputType.emailAddress, hints: const [AutofillHints.email]),
        if (_sent) ...[
          Text(context.t('code_sent_to', {'email': _email.text.trim()}), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Field(label: context.t('code'), controller: _code, error: _fields['code'], keyboard: TextInputType.number, maxLength: 6, hints: const [AutofillHints.oneTimeCode]),
          Field(label: context.t('new_password'), controller: _password, error: _fields['password'], obscure: true, maxLength: 128, help: context.t('password_rules'), hints: const [AutofillHints.newPassword]),
        ],
        BusyButton(label: _sent ? context.t('confirm') : context.t('send_code'), onPressed: _submit),
      ],
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final session = AppScope.read(context).session;
    if (await Biometric.confirm(context.t('confirm_it_is_you'))) {
      session.unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: Layout.page(context, top: 24, bottom: 24, gutter: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DisplayTitle(context.t('locked_a'), second: context.t('locked_b')),
                  const SizedBox(height: 20),
                  BusyButton(label: context.t('unlock'), onPressed: _unlock),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => AppScope.read(context).session.clear(),
                    child: Text(context.t('use_password'), style: TextStyle(color: Palette.muted)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key, required this.reason});

  /// A text key from strings.dart naming what was found.
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: Layout.page(context, top: 24, bottom: 24, gutter: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DisplayTitle(context.t('blocked_a'), second: context.t('blocked_b')),
                  const SizedBox(height: 12),
                  Text(context.t('blocked_body', {'reason': context.t(reason)}), textAlign: TextAlign.justify),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
