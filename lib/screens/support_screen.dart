import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/integrity.dart';
import '../core/layout.dart';
import '../core/payments.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_screens.dart';
import 'gift_status_screen.dart';

const _presets = [1000, 5000, 10000, 50000];
const _minimum = 500;
const _maximum = 10000000;

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _amount = TextEditingController(text: '5000');
  final _phone = TextEditingController();
  String _method = 'card';
  String? _campaign;
  List<Map<String, dynamic>> _campaigns = const [];
  List<Map<String, dynamic>>? _gifts;
  bool _wasSignedIn = false;
  String? _error;
  Map<String, String> _fields = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadCampaigns());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final signedIn = AppScope.of(context).session.signedIn;
    if (signedIn && !_wasSignedIn) {
      unawaited(_loadGifts());
    }
    _wasSignedIn = signedIn;
  }

  @override
  void dispose() {
    _amount.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadCampaigns() async {
    try {
      final data = await AppScope.read(context).cache.load('campaigns');
      if (mounted) {
        setState(() => _campaigns = [for (final row in (data['results'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)]);
      }
    } on ApiException {
      return;
    }
  }

  Future<void> _loadGifts() async {
    try {
      final data = await AppScope.read(context).api.get('donations', auth: true) as Map;
      if (mounted) {
        setState(() => _gifts = [for (final row in (data['results'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)]);
      }
    } on ApiException {
      return;
    }
  }

  Future<void> _give() async {
    final services = AppScope.read(context);
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final phone = _method == 'mobile' ? Payments.phone(_phone.text) : '';
    setState(() {
      _error = null;
      _fields = {
        if (amount < _minimum || amount > _maximum) 'amount': context.t('min_amount'),
        if (phone == null) 'phone': context.t('bad_phone'),
      };
    });
    if (_fields.isNotEmpty) {
      return;
    }
    // Mobile money on iPhone goes through the website in Safari, outside the app, as Apple asks of donation apps.
    if (Platform.isIOS && _method == 'mobile') {
      await Payments.openSecurePage(Payments.websiteGiving);
      return;
    }
    try {
      final data = Map<String, dynamic>.from(await services.api.post(
        'donations',
        auth: true,
        headers: await Integrity.headers(services.api),
        body: {'amount': amount, 'method': _method, 'phone': phone, 'platform': Platform.isIOS ? 'ios' : 'android', 'campaign': _campaign},
      ) as Map);
      final reference = (data['gift'] as Map)['reference'].toString();
      if (data['pay_url'] != null) {
        await Payments.openSecurePage(Uri.parse(data['pay_url'].toString()));
      }
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GiftStatusScreen(reference: reference)));
        unawaited(_loadGifts());
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
    final services = AppScope.of(context);
    final signedIn = services.session.signedIn;
    return RefreshIndicator(
      color: Palette.green,
      onRefresh: () async {
        await _loadCampaigns();
        if (signedIn) {
          await _loadGifts();
        }
      },
      child: ListView(
        padding: Layout.page(context, top: 16, bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DisplayTitle(context.t('support_a'), second: context.t('support_b')),
                const SizedBox(height: 10),
                Text(context.t('support_body'), textAlign: TextAlign.justify),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final campaign in _campaigns.take(3))
            Padding(padding: const EdgeInsets.only(bottom: 8), child: _CampaignCard(campaign: campaign, onGive: () => setState(() => _campaign = campaign['id'].toString()))),
          const SizedBox(height: 6),
          if (!signedIn)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.t('sign_in_give'), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  BusyButton(label: context.t('sign_in'), onPressed: () => openSignIn(context)),
                  const SizedBox(height: 8),
                  BusyButton(label: context.t('give_website'), style: BusyStyle.light, onPressed: () => Payments.openSecurePage(Payments.websiteGiving)),
                ],
              ),
            )
          else ...[
            Panel(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ErrorNote(_error),
                  Text(context.t('amount_tzs'), style: TextStyle(fontSize: 12.5, color: Palette.muted)),
                  const SizedBox(height: 8),
                  AdaptiveGrid(
                    minTileWidth: 64,
                    spacing: 6,
                    tileHeight: 42,
                    children: [
                      for (final value in _presets)
                        Material(
                          color: _amount.text == '$value' ? Palette.solid : Palette.stone,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _amount.text = '$value'),
                            child: Center(
                              child: Text(whole(value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _amount.text == '$value' ? Colors.white : Palette.ink)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    maxLength: 9,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(counterText: '', errorText: _fields['amount']),
                  ),
                  const SizedBox(height: 14),
                  Text(context.t('pay_with'), style: TextStyle(fontSize: 12.5, color: Palette.muted)),
                  const SizedBox(height: 8),
                  Segmented<String>(
                    height: 38,
                    options: [('card', context.t('card')), ('mobile', context.t('mobile_money'))],
                    value: _method,
                    onChanged: (value) => setState(() => _method = value),
                  ),
                  if (_method == 'mobile') ...[
                    const SizedBox(height: 12),
                    Field(label: context.t('phone'), controller: _phone, error: _fields['phone'], keyboard: TextInputType.phone, maxLength: 16, hints: const [AutofillHints.telephoneNumber]),
                  ],
                  if (_campaigns.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(context.t('give_towards'), style: TextStyle(fontSize: 12.5, color: Palette.muted)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      key: ValueKey(_campaign),
                      initialValue: _campaign,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(context.t('needed_most'))),
                        for (final campaign in _campaigns) DropdownMenuItem<String?>(value: campaign['id'].toString(), child: Text(campaign['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) => setState(() => _campaign = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  BusyButton(label: context.t('give_now'), style: BusyStyle.green, onPressed: _give),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
              child: Text(context.t('your_gifts').toUpperCase(), style: Theme.of(context).textTheme.headlineSmall),
            ),
            if (_gifts == null)
              const LoadView()
            else if (_gifts!.isEmpty)
              Panel(child: Text(context.t('no_gifts'), textAlign: TextAlign.center))
            else
              Panel(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < _gifts!.length; i++) ...[
                      if (i > 0) const Divider(indent: 14, endIndent: 14),
                      ListTile(
                        dense: true,
                        title: Text('TZS ${whole((_gifts![i]['amount'] as num?) ?? 0)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.ink)),
                        subtitle: Text(
                          [(_gifts![i]['campaign'] ?? '').toString(), (_gifts![i]['created_at'] ?? '').toString().split('T').first].where((part) => part.isNotEmpty).join('  |  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          context.t('status_${_gifts![i]['status']}'),
                          style: TextStyle(fontSize: 12, color: _gifts![i]['status'] == 'paid' ? Palette.green : (_gifts![i]['status'] == 'pending' ? Palette.muted : Palette.bad)),
                        ),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GiftStatusScreen(reference: _gifts![i]['reference'].toString()))),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign, required this.onGive});

  final Map<String, dynamic> campaign;
  final VoidCallback onGive;

  @override
  Widget build(BuildContext context) {
    final goal = (campaign['goal'] as num?) ?? 0;
    final raised = (campaign['raised'] as num?) ?? 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Palette.green, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('sponsor_book').toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: Palette.goldLight)),
          const SizedBox(height: 6),
          Text((campaign['title'] ?? '').toString().toUpperCase(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Colors.white)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: goal > 0 ? (raised / goal).clamp(0.0, 1.0).toDouble() : 0,
              minHeight: 5,
              backgroundColor: const Color(0x33FFFFFF),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(context.t('raised_of', {'raised': whole(raised), 'goal': whole(goal)}), style: const TextStyle(fontSize: 12, color: Color(0xBFFFFFFF))),
          const SizedBox(height: 10),
          Pill(label: context.t('give_now'), dark: false, onTap: onGive),
        ],
      ),
    );
  }
}
