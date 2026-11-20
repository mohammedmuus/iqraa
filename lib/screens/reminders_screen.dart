import 'package:flutter/material.dart';

import '../core/cities.dart';
import '../core/layout.dart';
import '../core/prayer_times.dart';
import '../core/reminders.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'qibla_screen.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  Future<void> _switch(BuildContext context, bool on) async {
    final services = AppScope.read(context);
    final reminders = services.reminders;
    if (!on) {
      await reminders.turnOff();
      return;
    }
    if (reminders.city == null) {
      final picked = await pickCity(context);
      if (picked == null || !context.mounted) {
        return;
      }
    }
    final allowed = await reminders.turnOn(services.prefs.language);
    if (!allowed && context.mounted) {
      showMessage(context, context.t('reminders_blocked'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final reminders = services.reminders;
    final language = services.prefs.language;
    final city = reminders.city;
    final today = reminders.today;
    final labels = {
      ReminderKind.afterFajr: ('rem_kind_fajr', 'rem_kind_fajr_note'),
      ReminderKind.evening: ('rem_kind_evening', 'rem_kind_evening_note'),
      ReminderKind.tahajjud: ('rem_kind_tahajjud', 'rem_kind_tahajjud_note'),
      ReminderKind.hourly: ('rem_kind_hourly', 'rem_kind_hourly_note'),
      ReminderKind.friday: ('rem_kind_friday', 'rem_kind_friday_note'),
      ReminderKind.fasting: ('rem_kind_fasting', 'rem_kind_fasting_note'),
    };
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
                    DisplayTitle(context.t('reminders_a'), second: context.t('reminders_b'), size: 30),
                    const SizedBox(height: 6),
                    Text(context.t('reminders_intro'), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: Palette.green,
                      value: reminders.enabled,
                      title: Text(context.t('reminders_on'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      onChanged: (value) => _switch(context, value),
                    ),
                    const Divider(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.t('city'), style: const TextStyle(fontSize: 14)),
                      trailing: Text(city == null ? context.t('choose_city') : city.name, style: TextStyle(color: Palette.muted)),
                      onTap: () => pickCity(context),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.t('calc_method'), style: const TextStyle(fontSize: 14)),
                      subtitle: Text(reminders.method.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Palette.muted)),
                      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: Palette.muted),
                      onTap: () => _pickMethod(context),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.t('qibla_direction'), style: const TextStyle(fontSize: 14)),
                      trailing: Icon(Icons.explore_outlined, size: 20, color: Palette.green),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QiblaScreen())),
                    ),
                    const SizedBox(height: 6),
                    Text(context.t('asr_time'), style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Segmented<AsrMethod>(
                      options: [(AsrMethod.standard, context.t('asr_standard')), (AsrMethod.hanafi, context.t('asr_hanafi'))],
                      value: reminders.asr,
                      onChanged: (value) => reminders.setAsr(value, language),
                    ),
                  ],
                ),
              ),
              if (today != null) ...[
                const SizedBox(height: 12),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.t('today_times'), style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(context.t('times_on_phone'), style: Theme.of(context).textTheme.bodySmall),
                      Text(context.t('times_tap_to_change'), style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (key, time) in [
                            ('fajr', today.fajr),
                            ('sunrise', today.sunrise),
                            ('dhuhr', today.dhuhr),
                            ('asr', today.asr),
                            ('maghrib', today.maghrib),
                            ('isha', today.isha),
                          ])
                            _Time(
                              label: context.t('prayer_$key'),
                              time: time,
                              typed: reminders.overrides.containsKey(key),
                              onTap: () => _changeTime(context, key, time),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Panel(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: Palette.green,
                      value: reminders.adhan,
                      title: Text(context.t('rem_kind_adhan'), style: const TextStyle(fontSize: 14)),
                      subtitle: Text(context.t('adhan_note'), style: TextStyle(fontSize: 12, color: Palette.muted)),
                      onChanged: (value) async {
                        await reminders.setAdhan(value, language);
                        if (value && !reminders.enabled && context.mounted) {
                          await _switch(context, true);
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: Palette.green,
                      value: reminders.reading,
                      title: Text(context.t('rem_kind_reading'), style: const TextStyle(fontSize: 14)),
                      subtitle: Text(context.t('rem_kind_reading_note'), style: TextStyle(fontSize: 12, color: Palette.muted)),
                      onChanged: (value) => reminders.setReading(value, language),
                    ),
                    for (final kind in ReminderKind.values)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeTrackColor: Palette.green,
                        value: reminders.kinds.contains(kind),
                        title: Text(context.t(labels[kind]!.$1), style: const TextStyle(fontSize: 14)),
                        subtitle: Text(context.t(labels[kind]!.$2), style: TextStyle(fontSize: 12, color: Palette.muted)),
                        onChanged: (value) => reminders.toggle(kind, value, language),
                      ),
                    if (services.session.signedIn)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeTrackColor: Palette.green,
                        value: services.rivals.enabled,
                        title: Text(context.t('rem_kind_rivals'), style: const TextStyle(fontSize: 14)),
                        subtitle: Text(context.t('rem_kind_rivals_note'), style: TextStyle(fontSize: 12, color: Palette.muted)),
                        onChanged: (value) async {
                          if (value) {
                            await services.reminders.askPermission();
                          }
                          await services.rivals.setEnabled(value);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickMethod(BuildContext context) {
    final services = AppScope.read(context);
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
              Text(sheet.t('calc_method'), style: Theme.of(sheet).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final method in PrayerMethod.values)
                ListTile(
                  title: Text(method.label, style: TextStyle(fontSize: 14, color: Palette.ink)),
                  trailing: services.reminders.method == method ? Icon(Icons.check_rounded, color: Palette.green, size: 20) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () {
                    services.reminders.setMethod(method, services.prefs.language);
                    Navigator.of(sheet).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets the reader pick their city from a searchable list. Returns the city picked, or null.
Future<City?> pickCity(BuildContext context) {
  final services = AppScope.read(context);
  return showModalBottomSheet<City>(
    context: context,
    backgroundColor: Palette.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => _CitySheet(
      current: services.reminders.cityId,
      onPick: (city) async {
        await services.reminders.setCity(city.id, services.prefs.language);
        if (sheet.mounted) {
          Navigator.of(sheet).pop(city);
        }
      },
    ),
  );
}

class _CitySheet extends StatefulWidget {
  const _CitySheet({required this.current, required this.onPick});

  final String? current;
  final ValueChanged<City> onPick;

  @override
  State<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends State<_CitySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final cities = [
      for (final city in City.all)
        if (query.isEmpty || city.name.toLowerCase().contains(query) || city.country.toLowerCase().contains(query)) city,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Text(context.t('choose_city'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded, size: 20), hintText: context.t('search_city'), isDense: true),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: cities.isEmpty
                    ? Center(child: Text(context.t('no_city'), textAlign: TextAlign.center))
                    : ListView.builder(
                        itemCount: cities.length,
                        itemBuilder: (context, index) {
                          final city = cities[index];
                          return ListTile(
                            dense: true,
                            title: Text(city.name, style: TextStyle(fontSize: 14, color: Palette.ink)),
                            subtitle: Text(city.country, style: TextStyle(fontSize: 12, color: Palette.muted)),
                            trailing: city.id == widget.current ? Icon(Icons.check_rounded, color: Palette.green, size: 20) : null,
                            onTap: () => widget.onPick(city),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Time extends StatelessWidget {
  const _Time({required this.label, required this.time, required this.onTap, this.typed = false});

  final String label;
  final DateTime time;
  final VoidCallback onTap;

  /// Set by the reader rather than worked out.
  final bool typed;

  @override
  Widget build(BuildContext context) {
    final local = time.toLocal();
    final clock = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Material(
      color: typed ? Palette.greenSoft : Palette.canvas,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Palette.muted))),
                  Icon(typed ? Icons.edit_rounded : Icons.edit_outlined, size: 12, color: typed ? Palette.green : Palette.muted),
                ],
              ),
              const SizedBox(height: 2),
              Text(clock, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets the reader type a prayer time by hand, or go back to the worked out time.
Future<void> _changeTime(BuildContext context, String prayer, DateTime shown) async {
  final services = AppScope.read(context);
  final reminders = services.reminders;
  final language = services.prefs.language;
  if (reminders.overrides.containsKey(prayer)) {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: Text(context.t('time_change')), onTap: () => Navigator.of(sheet).pop('change')),
            ListTile(leading: const Icon(Icons.restore_rounded), title: Text(context.t('time_reset')), onTap: () => Navigator.of(sheet).pop('reset')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'reset') {
      await reminders.setOverride(prayer, null, language);
      return;
    }
    if (choice != 'change' || !context.mounted) {
      return;
    }
  }
  final local = shown.toLocal();
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: local.hour, minute: local.minute),
    initialEntryMode: TimePickerEntryMode.input,
    helpText: context.t('time_for', {'prayer': context.t('prayer_$prayer')}),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  if (picked != null) {
    await reminders.setOverride(prayer, (picked.hour, picked.minute), language);
  }
}
