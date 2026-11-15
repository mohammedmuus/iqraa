import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/layout.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Follows a gift until the bank or the mobile money provider confirms it. Checks again when the app returns.
class GiftStatusScreen extends StatefulWidget {
  const GiftStatusScreen({super.key, required this.reference});

  final String reference;

  @override
  State<GiftStatusScreen> createState() => _GiftStatusScreenState();
}

class _GiftStatusScreenState extends State<GiftStatusScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _gift;
  Timer? _timer;
  int _checks = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checks = 0;
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    _timer?.cancel();
    try {
      final data = await AppScope.read(context).api.get('donations/${widget.reference}', auth: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _gift = Map<String, dynamic>.from(data as Map);
        _error = null;
      });
      if (_gift!['status'] != 'pending') {
        return;
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = context.describe(error));
      }
    }
    _checks += 1;
    if (_checks < 40 && mounted) {
      _timer = Timer(Duration(seconds: _checks < 10 ? 3 : 8), _check);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gift = _gift;
    final status = gift?['status'] as String? ?? 'pending';
    final paid = status == 'paid';
    final waiting = status == 'pending';
    final amount = whole((gift?['amount'] as num?) ?? 0);
    final body = paid
        ? context.t('gift_paid_body', {'amount': amount})
        : waiting
            ? (gift?['method'] == 'mobile' ? context.t('gift_wait_phone', {'phone': gift?['phone'] ?? '', 'amount': amount}) : context.t('gift_wait_card'))
            : context.t('gift_failed');
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: ListView(
            padding: Layout.page(context, top: 8, bottom: 28),
            children: [
              Row(children: [RoundButton(icon: Icons.arrow_back_rounded, label: context.t('back'), onTap: () => Navigator.of(context).maybePop())]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: paid ? Palette.green : Palette.surface, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (waiting) ...[
                      LinearProgressIndicator(minHeight: 3, backgroundColor: Palette.stone),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      paid ? context.t('gift_thanks') : context.t('gift_title'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 28, color: paid ? Colors.white : Palette.ink),
                    ),
                    const SizedBox(height: 10),
                    Text(body, textAlign: TextAlign.justify, style: TextStyle(height: 1.55, color: paid ? const Color(0xE6FFFFFF) : Palette.body)),
                    const SizedBox(height: 14),
                    Text(context.t('reference', {'ref': widget.reference}), style: TextStyle(fontSize: 12, color: paid ? const Color(0xB3FFFFFF) : Palette.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ErrorNote(_error),
              if (waiting)
                BusyButton(
                  label: context.t('check_again'),
                  style: BusyStyle.light,
                  onPressed: () async {
                    _checks = 0;
                    await _check();
                  },
                )
              else
                BusyButton(label: paid ? context.t('done') : context.t('back'), style: paid ? BusyStyle.green : BusyStyle.dark, onPressed: () async => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}
