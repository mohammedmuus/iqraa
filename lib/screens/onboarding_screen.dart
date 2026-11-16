import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/layout.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'reminders_screen.dart';

const _doneKey = 'onboarded';

/// Shows the three first-run choices once: language, city and daily dhikr goal.
Future<void> onboardIfNew(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_doneKey) ?? false) {
    return;
  }
  if (context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const OnboardingScreen()));
  }
}

/// Lets the reader pick their own daily goal for every dhikr, or go back to each one's suggested goal.
Future<void> pickGoal(BuildContext context) {
  final store = AppScope.read(context).dhikr;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.surface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: _GoalChoices(
          current: store.goal,
          onPick: (value) {
            store.setGoal(value);
            Navigator.of(sheet).pop();
          },
        ),
      ),
    ),
  );
}

class _GoalChoices extends StatelessWidget {
  const _GoalChoices({required this.current, required this.onPick});

  static const goals = [null, 33, 100, 300, 1000];

  final int? current;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final goal in goals)
          ListTile(
            dense: true,
            title: Text(goal == null ? context.t('goal_suggested') : context.t('goal_n', {'n': goal}), style: TextStyle(fontSize: 14, color: Palette.ink)),
            trailing: current == goal ? Icon(Icons.check_rounded, color: Palette.green, size: 20) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => onPick(goal),
          ),
      ],
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _reminders = true;
  bool _adhan = false;

  Future<void> _finish() async {
    final services = AppScope.read(context);
    await (await SharedPreferences.getInstance()).setBool(_doneKey, true);
    final reminders = services.reminders;
    if ((_reminders || _adhan) && reminders.city != null && !reminders.enabled) {
      if (!_reminders) {
        await reminders.setKinds(const {}, services.prefs.language);
      }
      await reminders.turnOn(services.prefs.language);
    }
    if (_adhan && reminders.enabled) {
      await reminders.setAdhan(true, services.prefs.language);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final steps = [_language(context, services), _city(context, services), _goal(context, services)];
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: Padding(
            padding: Layout.page(context, top: 8, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        width: i == _step ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(color: i <= _step ? Palette.green : Palette.line, borderRadius: BorderRadius.circular(4)),
                      ),
                    const Spacer(),
                    TextButton(onPressed: _finish, child: Text(context.t('skip'), style: TextStyle(color: Palette.muted))),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: SingleChildScrollView(key: ValueKey(_step), child: steps[_step]),
                  ),
                ),
                const SizedBox(height: 12),
                PairRow(
                  first: BusyButton(label: context.t('back'), style: BusyStyle.light, onPressed: _step == 0 ? null : () async => setState(() => _step--)),
                  second: BusyButton(
                    label: _step == steps.length - 1 ? context.t('start') : context.t('next'),
                    onPressed: () async => _step == steps.length - 1 ? _finish() : setState(() => _step++),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(body, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _language(BuildContext context, AppServices services) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, context.t('onb_lang_title'), ''),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final code in Strings.names.keys)
                ListTile(
                  title: Text(Strings.names[code]!, style: TextStyle(fontSize: 15, color: Palette.ink)),
                  trailing: services.prefs.language == code ? Icon(Icons.check_rounded, color: Palette.green, size: 20) : null,
                  onTap: () => services.prefs.setLanguage(code),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _city(BuildContext context, AppServices services) {
    final city = services.reminders.city;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, context.t('onb_city_title'), context.t('onb_city_body')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.t('city'), style: const TextStyle(fontSize: 14)),
                trailing: Text(city == null ? context.t('choose_city') : city.name, style: TextStyle(color: Palette.green, fontWeight: FontWeight.w600)),
                onTap: () => pickCity(context),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: Palette.green,
                value: _reminders,
                title: Text(context.t('onb_reminders'), style: const TextStyle(fontSize: 14)),
                onChanged: (value) => setState(() => _reminders = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: Palette.green,
                value: _adhan,
                title: Text(context.t('onb_adhan'), style: const TextStyle(fontSize: 14)),
                subtitle: Text(context.t('adhan_note'), style: TextStyle(fontSize: 12, color: Palette.muted)),
                onChanged: (value) => setState(() => _adhan = value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _goal(BuildContext context, AppServices services) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, context.t('onb_goal_title'), context.t('onb_goal_body')),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _GoalChoices(current: services.dhikr.goal, onPick: services.dhikr.setGoal),
        ),
      ],
    );
  }
}
