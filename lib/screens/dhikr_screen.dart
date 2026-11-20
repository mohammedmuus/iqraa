import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/layout.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_screens.dart';
import 'onboarding_screen.dart';

enum _View { adhkar, rankings, groups }

/// Countries offered for the country board. Names are proper nouns and stay as written.
const countryNames = {
  'TZ': 'Tanzania', 'KE': 'Kenya', 'UG': 'Uganda', 'RW': 'Rwanda', 'BI': 'Burundi', 'CD': 'DR Congo', 'MZ': 'Mozambique',
  'MW': 'Malawi', 'ZM': 'Zambia', 'KM': 'Comoros', 'SO': 'Somalia', 'ET': 'Ethiopia', 'SD': 'Sudan', 'EG': 'Egypt',
  'LY': 'Libya', 'TN': 'Tunisia', 'DZ': 'Algeria', 'MA': 'Morocco', 'NG': 'Nigeria', 'GH': 'Ghana', 'SN': 'Senegal',
  'ML': 'Mali', 'NE': 'Niger', 'ZA': 'South Africa', 'SA': 'Saudi Arabia', 'AE': 'United Arab Emirates', 'OM': 'Oman',
  'QA': 'Qatar', 'KW': 'Kuwait', 'BH': 'Bahrain', 'YE': 'Yemen', 'JO': 'Jordan', 'IQ': 'Iraq', 'SY': 'Syria', 'LB': 'Lebanon',
  'PS': 'Palestine', 'TR': 'Turkey', 'IR': 'Iran', 'PK': 'Pakistan', 'AF': 'Afghanistan', 'IN': 'India', 'BD': 'Bangladesh',
  'ID': 'Indonesia', 'MY': 'Malaysia', 'GB': 'United Kingdom', 'US': 'United States', 'CA': 'Canada', 'FR': 'France',
  'DE': 'Germany', 'AU': 'Australia',
};

class DhikrScreen extends StatefulWidget {
  const DhikrScreen({super.key, this.reselect});

  /// Ticks when the Dhikr tab is tapped again, which brings the reader back to the adhkar at the top.
  final Listenable? reselect;

  @override
  State<DhikrScreen> createState() => _DhikrScreenState();
}

class _DhikrScreenState extends State<DhikrScreen> {
  _View _view = _View.adhkar;
  String? _selected;
  Object? _error;
  bool _synced = false;
  final ScrollController _scroll = ScrollController();
  final GlobalKey<_BoardsState> _boards = GlobalKey<_BoardsState>();
  final GlobalKey<_GroupsState> _groups = GlobalKey<_GroupsState>();

  @override
  void initState() {
    super.initState();
    widget.reselect?.addListener(_backToAdhkar);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(DhikrScreen old) {
    super.didUpdateWidget(old);
    if (old.reselect != widget.reselect) {
      old.reselect?.removeListener(_backToAdhkar);
      widget.reselect?.addListener(_backToAdhkar);
    }
  }

  @override
  void dispose() {
    widget.reselect?.removeListener(_backToAdhkar);
    _scroll.dispose();
    super.dispose();
  }

  void _backToAdhkar() {
    setState(() {
      _view = _View.adhkar;
      _selected = null;
    });
    _toTop();
  }

  void _toTop() {
    if (_scroll.hasClients && _scroll.offset > 0) {
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (services.session.signedIn && !_synced) {
      _synced = true;
      unawaited(services.dhikr.sync());
    } else if (!services.session.signedIn && _synced) {
      _synced = false;
      services.dhikr.forgetAccount();
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await AppScope.read(context).dhikr.loadAdhkar();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  /// Pulling down reloads whichever section is open.
  Future<void> _refresh() async {
    final signedIn = AppScope.read(context).session.signedIn;
    switch (_view) {
      case _View.adhkar:
        await _load();
        if (signedIn && mounted) {
          await AppScope.read(context).dhikr.sync();
        }
      case _View.rankings:
        await _boards.currentState?._load(keep: true);
      case _View.groups:
        await _groups.currentState?._load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final store = services.dhikr;
    final selected = store.adhkar.where((d) => d['slug'] == _selected).firstOrNull;
    final side = Layout.page(context);
    final Widget body;
    if (_view == _View.adhkar) {
      body = store.adhkar.isEmpty
          ? LoadView(error: _error, onRetry: _load)
          : selected != null
          ? _Counter(dhikr: selected, onBack: () => setState(() => _selected = null))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (store.profile != null) _Totals(profile: store.profile!),
                AdaptiveGrid(
                  minTileWidth: 150,
                  spacing: 8,
                  children: [
                    for (final dhikr in store.adhkar)
                      _DhikrTile(
                        dhikr: dhikr,
                        onTap: () {
                          setState(() => _selected = dhikr['slug'].toString());
                          _toTop();
                        },
                      ),
                  ],
                ),
              ],
            );
    } else if (!services.session.signedIn) {
      body = Panel(
        child: Column(
          children: [
            Text(context.t('sign_in_boards'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            BusyButton(label: context.t('sign_in'), onPressed: () => openSignIn(context)),
          ],
        ),
      );
    } else {
      body = _view == _View.rankings ? _Boards(key: _boards) : _Groups(key: _groups);
    }
    return PullRefresh(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side.left + 8, 16, side.right, 14),
            sliver: SliverToBoxAdapter(child: DisplayTitle(context.t('dhikr_a'), second: context.t('dhikr_b'))),
          ),
          // The three sections stay at the top while the reader scrolls, so they can always switch.
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedTabs(
              padding: EdgeInsets.fromLTRB(side.left, 6, side.right, 6),
              child: Segmented<_View>(
                height: 34,
                options: [(_View.adhkar, context.t('dhikr_count')), (_View.rankings, context.t('dhikr_boards')), (_View.groups, context.t('dhikr_groups'))],
                value: _view,
                onChanged: (value) {
                  setState(() {
                    _view = value;
                    _selected = null;
                  });
                  _toTop();
                },
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side.left, 6, side.right, 28),
            sliver: SliverToBoxAdapter(child: body),
          ),
        ],
      ),
    );
  }
}

class _PinnedTabs extends SliverPersistentHeaderDelegate {
  const _PinnedTabs({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  double get minExtent => 46 + padding.vertical;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: Palette.canvas,
      child: Padding(padding: padding, child: Center(child: child)),
    );
  }

  @override
  bool shouldRebuild(_PinnedTabs old) => true;
}

class _Totals extends StatelessWidget {
  const _Totals({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final streak = (profile['streak_days'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [context.t('week_total', {'n': whole((profile['week_total'] as num?) ?? 0)}), if (streak > 1) context.t('streak', {'n': streak})].join('  |  '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (streak > 1 && profile['streak_kept'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(context.t('streak_kept'), style: TextStyle(fontSize: 12, color: Palette.green)),
            ),
        ],
      ),
    );
  }
}

String _meaning(BuildContext context, Map<String, dynamic> dhikr) {
  final language = AppScope.of(context).prefs.language;
  return language == 'ar' ? '' : (dhikr[language == 'sw' ? 'meaning_sw' : 'meaning_en'] ?? '').toString();
}

class _DhikrTile extends StatelessWidget {
  const _DhikrTile({required this.dhikr, required this.onTap});

  final Map<String, dynamic> dhikr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).dhikr;
    final goal = store.goalFor(dhikr);
    final count = store.today(dhikr['slug'].toString());
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 62, child: Align(alignment: Alignment.centerRight, child: ArabicText((dhikr['arabic'] ?? '').toString(), size: 19, height: 1.6, maxLines: 2))),
              const SizedBox(height: 6),
              Text((dhikr['label'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Palette.ink)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: goal > 0 ? (count / goal).clamp(0.0, 1.0) : 0, minHeight: 4, backgroundColor: Palette.stone),
              ),
              const SizedBox(height: 5),
              Text(context.t('today_goal', {'count': whole(count), 'goal': whole(goal)}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Palette.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.dhikr, required this.onBack});

  final Map<String, dynamic> dhikr;
  final VoidCallback onBack;

  void _count(BuildContext context, int count, int goal) {
    final store = AppScope.read(context).dhikr;
    store.add(dhikr['slug'].toString());
    if (count + 1 == goal) {
      HapticFeedback.heavyImpact();
      unawaited(celebrate(context, context.t('goal_reached')));
    } else {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).dhikr;
    final slug = dhikr['slug'].toString();
    final goal = store.goalFor(dhikr);
    final count = store.today(slug);
    final meaning = _meaning(context, dhikr);
    return Column(
      children: [
        Row(children: [RoundButton(icon: Icons.arrow_back_rounded, label: context.t('back'), onTap: onBack)]),
        const SizedBox(height: 10),
        Panel(
          child: Column(
            children: [
              SizedBox(width: double.infinity, child: ArabicText((dhikr['arabic'] ?? '').toString(), size: (dhikr['arabic'] ?? '').toString().length > 120 ? 21 : 28, height: 1.8, align: TextAlign.center)),
              if (meaning.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(meaning, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final size = math.min(box.maxWidth * 0.8, 280.0);
            return Semantics(
              button: true,
              label: '${dhikr['label']}, ${context.t('today_goal', {'count': count, 'goal': goal})}',
              child: GestureDetector(
                onTap: () => _count(context, count, goal),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: _Ring(goal > 0 ? (count / goal).clamp(0.0, 1.0) : 0),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(child: Text(whole(count), style: TextStyle(fontSize: size * 0.22, fontWeight: FontWeight.w500, letterSpacing: -2, color: Palette.ink))),
                          Text(context.t('today_goal', {'count': whole(count), 'goal': whole(goal)}), style: TextStyle(fontSize: 12, color: Palette.muted)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Text(context.t('tap_to_count'), style: Theme.of(context).textTheme.bodySmall),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (count > 0)
              TextButton(
                onPressed: () => store.add(slug, -1),
                child: Text(context.t('undo'), style: TextStyle(color: Palette.muted)),
              ),
            TextButton(
              onPressed: () => pickGoal(context),
              child: Text(context.t('change_goal'), style: TextStyle(color: Palette.muted)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring(this.share);

  final double share;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(centre, radius, Paint()..color = Palette.surface);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = Palette.stone;
    canvas.drawCircle(centre, radius - 14, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = Palette.green;
    canvas.drawArc(Rect.fromCircle(center: centre, radius: radius - 14), -math.pi / 2, 2 * math.pi * share, false, arc);
  }

  @override
  bool shouldRepaint(_Ring old) => old.share != share;
}

/// Worldwide and country rankings. Nobody appears until they join, and names show only if the reader turns them on.
class _Boards extends StatefulWidget {
  const _Boards({super.key});

  @override
  State<_Boards> createState() => _BoardsState();
}

class _BoardsState extends State<_Boards> {
  String _kind = 'worldwide';
  String _week = 'current';
  String _filter = '';
  Map<String, dynamic>? _board;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// [keep] leaves the current board on screen while a pull down reload runs.
  Future<void> _load({bool keep = false}) async {
    setState(() {
      if (!keep) {
        _board = null;
      }
      _error = null;
    });
    try {
      final data = await AppScope.read(context).api.get('dhikr/boards/$_kind', auth: true, query: {'week': _week, if (_filter.isNotEmpty) 'dhikr': _filter});
      if (mounted) {
        setState(() => _board = Map<String, dynamic>.from(data as Map));
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _update(Map<String, dynamic> changes) async {
    try {
      await AppScope.read(context).dhikr.updateProfile(changes);
      if (mounted) {
        unawaited(_load());
      }
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  Future<void> _setCountry(String code) async {
    final services = AppScope.read(context);
    try {
      await services.api.patch('me', body: {'country': code}, auth: true);
      await services.dhikr.sync();
      if (mounted) {
        unawaited(_load());
      }
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).dhikr;
    final profile = store.profile;
    final onBoards = profile?['on_boards'] == true;
    final rows = [for (final row in (_board?['rows'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
    final you = _board?['you'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Intention(),
        if (profile != null && !onBoards) ...[
          const SizedBox(height: 8),
          BusyButton(label: context.t('join_boards'), style: BusyStyle.green, onPressed: () => _update({'accept_notice': true, 'on_boards': true})),
          const SizedBox(height: 6),
          Text(context.t('off_boards'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (profile != null && onBoards) ...[
          const SizedBox(height: 10),
          _Appearance(profile: profile, onUpdate: _update, onCountry: _setCountry),
        ],
        const SizedBox(height: 12),
        Segmented<String>(
          options: [('worldwide', context.t('worldwide')), ('countries', context.t('countries'))],
          value: _kind,
          onChanged: (value) {
            setState(() => _kind = value);
            unawaited(_load());
          },
        ),
        const SizedBox(height: 8),
        PairRow(
          first: Segmented<String>(
            options: [('current', context.t('this_week')), ('last', context.t('last_week'))],
            value: _week,
            onChanged: (value) {
              setState(() => _week = value);
              unawaited(_load());
            },
          ),
          second: DropdownButtonFormField<String>(
            initialValue: _filter,
            isExpanded: true,
            items: [
              DropdownMenuItem(value: '', child: Text(context.t('all_adhkar'))),
              for (final dhikr in store.adhkar) DropdownMenuItem(value: dhikr['slug'].toString(), child: Text(dhikr['label'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) {
              setState(() => _filter = value ?? '');
              unawaited(_load());
            },
          ),
        ),
        const SizedBox(height: 10),
        if (_kind == 'worldwide' && _board != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              you is Map ? context.t('your_rank', {'rank': you['rank'], 'total': whole(you['total'] as num)}) : context.t('not_ranked'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Palette.ink),
            ),
          ),
        if (_board == null)
          LoadView(error: _error, onRetry: _load)
        else
          BoardList(rows: rows, countries: _kind == 'countries'),
        if (profile != null && onBoards)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: TextButton(onPressed: () => _update({'on_boards': false}), child: Text(context.t('leave_boards'), style: TextStyle(color: Palette.muted))),
            ),
          ),
      ],
    );
  }
}

/// One short line about intention, shown above the rankings and group rankings.
class _Intention extends StatelessWidget {
  const _Intention();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Palette.greenSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.favorite_border_rounded, size: 16, color: Palette.greenDeep),
          const SizedBox(width: 10),
          Expanded(child: Text(context.t('riya_notice'), style: TextStyle(fontSize: 13, color: Palette.greenDeep))),
        ],
      ),
    );
  }
}

/// The name switch and country, in one small card. The name is the one on the account.
class _Appearance extends StatelessWidget {
  const _Appearance({required this.profile, required this.onUpdate, required this.onCountry});

  final Map<String, dynamic> profile;
  final Future<void> Function(Map<String, dynamic>) onUpdate;
  final Future<void> Function(String) onCountry;

  @override
  Widget build(BuildContext context) {
    final name = (profile['display_name'] ?? '').toString().trim();
    final showing = profile['show_name'] == true;
    final shown = displayName(context, (profile['public_name'] ?? profile['handle'] ?? '').toString());
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: showing && name.isNotEmpty,
            activeTrackColor: Palette.green,
            title: Text(context.t('show_name'), style: TextStyle(fontSize: 14, color: Palette.ink)),
            subtitle: Text(name.isEmpty ? context.t('name_needed') : context.t('shown_as', {'name': shown}), style: Theme.of(context).textTheme.bodySmall),
            onChanged: name.isEmpty ? null : (value) => onUpdate({'show_name': value}),
          ),
          DropdownButtonFormField<String>(
            initialValue: countryNames.containsKey(profile['country']) ? profile['country'].toString() : '',
            isExpanded: true,
            decoration: InputDecoration(labelText: context.t('country')),
            items: [
              DropdownMenuItem(value: '', child: Text(context.t('no_country'))),
              for (final entry in countryNames.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => onCountry(value ?? ''),
          ),
        ],
      ),
    );
  }
}

/// Shows the server's "Muumin 123456" handle with the word in the reader's language.
String displayName(BuildContext context, String name) {
  const prefix = 'Muumin ';
  return name.startsWith(prefix) ? '${context.t('muumin')} ${name.substring(prefix.length)}' : name;
}

class BoardList extends StatelessWidget {
  const BoardList({super.key, required this.rows, this.countries = false});

  final List<Map<String, dynamic>> rows;
  final bool countries;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Panel(child: Text(context.t('board_empty'), textAlign: TextAlign.center));
    }
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(indent: 14, endIndent: 14),
            Container(
              color: rows[i]['you'] == true ? Palette.greenSoft : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  SizedBox(width: 30, child: Text('${rows[i]['rank']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.muted))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          countries ? (_countryName(rows[i]['country'])) : (rows[i]['you'] == true ? '${displayName(context, (rows[i]['name'] ?? '').toString())} (${context.t('you_label')})' : displayName(context, (rows[i]['name'] ?? '').toString())),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Palette.ink),
                        ),
                        if (countries) Text(context.t('people_n', {'n': rows[i]['people'] ?? 0}), style: TextStyle(fontSize: 11, color: Palette.muted)),
                      ],
                    ),
                  ),
                  if (rows[i]['change'] is num && rows[i]['change'] != 0) _Move((rows[i]['change'] as num).toInt()),
                  Text(whole((rows[i]['total'] as num?) ?? 0), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Palette.ink)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _countryName(Object? code) => countryNames[code] ?? (code ?? '').toString();
}

class _Groups extends StatefulWidget {
  const _Groups({super.key});

  @override
  State<_Groups> createState() => _GroupsState();
}

class _GroupsState extends State<_Groups> {
  List<Map<String, dynamic>>? _groups;
  Object? _error;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await AppScope.read(context).api.get('dhikr/groups', auth: true);
      if (mounted) {
        setState(() => _groups = [for (final row in (data as List)) Map<String, dynamic>.from(row as Map)]);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _run(Future<Object?> Function() call, {String? done}) async {
    try {
      await call();
      if (mounted) {
        if (done != null) {
          showMessage(context, done);
        }
        unawaited(_load());
      }
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final api = services.api;
    final groups = _groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups == null)
          LoadView(error: _error, onRetry: _load)
        else if (groups.isEmpty)
          Panel(child: Text(context.t('no_groups'), textAlign: TextAlign.center))
        else
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(group['name'].toString(), style: Theme.of(context).textTheme.titleMedium),
                    Text(context.t('members_n', {'n': group['members'] ?? 0}), style: Theme.of(context).textTheme.bodySmall),
                    if (group['invite_url'] != null) ...[
                      const SizedBox(height: 4),
                      Text('${context.t('invite_code')}: ${group['invite_code']}', style: TextStyle(fontSize: 12, letterSpacing: 1, color: Palette.muted)),
                      const SizedBox(height: 8),
                      PairRow(
                        first: BusyButton(label: context.t('share_whatsapp'), style: BusyStyle.green, onPressed: () => shareInvite(context, group)),
                        second: BusyButton(
                          label: context.t('copy_link'),
                          style: BusyStyle.light,
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: group['invite_url'].toString()));
                            if (context.mounted) {
                              showMessage(context, context.t('link_copied'));
                            }
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    PairRow(
                      first: BusyButton(
                        label: context.t('dhikr_boards'),
                        onPressed: () async => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupBoardScreen(group: group))),
                      ),
                      second: BusyButton(
                        label: group['owner'] == true ? context.t('close_group') : context.t('leave_group'),
                        style: BusyStyle.light,
                        onPressed: () => _run(() async {
                          await api.post('dhikr/groups/${group['id']}/leave', auth: true);
                          unawaited(groupsChanged(services));
                          return null;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _name, maxLength: 60, decoration: InputDecoration(counterText: '', hintText: context.t('group_name'))),
              const SizedBox(height: 8),
              BusyButton(
                label: context.t('create_group'),
                onPressed: () => _run(() async {
                  final result = await api.post('dhikr/groups', body: {'name': _name.text.trim()}, auth: true);
                  _name.clear();
                  unawaited(groupsChanged(services, joined: true));
                  return result;
                }),
              ),
              const Divider(height: 28),
              TextField(
                controller: _code,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(counterText: '', hintText: context.t('code_hint'), labelText: context.t('invite_code')),
              ),
              const SizedBox(height: 8),
              BusyButton(
                label: context.t('join_group'),
                style: BusyStyle.light,
                onPressed: () async {
                  try {
                    final data = Map<String, dynamic>.from(await api.post('dhikr/groups/join', body: {'code': _code.text.trim()}, auth: true) as Map);
                    _code.clear();
                    unawaited(groupsChanged(services, joined: true));
                    if (mounted) {
                      showMessage(this.context, this.context.t('joined', {'name': data['name'] ?? ''}));
                      unawaited(_load());
                    }
                  } on ApiException catch (error) {
                    if (mounted) {
                      showMessage(this.context, this.context.describe(error));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sends a group invite through WhatsApp, which most readers use to share.
Future<void> shareInvite(BuildContext context, Map<String, dynamic> group) async {
  final message = context.t('invite_message', {'name': group['name'] ?? '', 'link': group['invite_url'] ?? ''});
  await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'), mode: LaunchMode.externalApplication);
}

/// Joins a group from an invite code or link and opens its weekly ladder.
/// After joining, starting or leaving a group. Joining asks once for permission to notify, so the reader hears
/// when a friend passes them, then the group check starts or stops.
Future<void> groupsChanged(AppServices services, {bool joined = false}) async {
  if (joined && services.rivals.enabled) {
    await services.reminders.askPermission();
  }
  await services.rivals.sync();
}

Future<void> joinGroup(NavigatorState navigator, AppServices services, String code) async {
  final context = navigator.context;
  try {
    final group = Map<String, dynamic>.from(await services.api.post('dhikr/groups/join', body: {'code': code}, auth: true) as Map);
    unawaited(groupsChanged(services, joined: true));
    if (context.mounted) {
      showMessage(context, context.t('joined', {'name': group['name'] ?? ''}));
    }
    await navigator.push(MaterialPageRoute<void>(builder: (_) => GroupBoardScreen(group: group)));
  } on ApiException catch (error) {
    if (context.mounted) {
      showMessage(context, context.describe(error));
    }
  }
}

/// Places moved on the group board since yesterday: up in green, down in a muted red.
class _Move extends StatelessWidget {
  const _Move(this.places);

  final int places;

  @override
  Widget build(BuildContext context) {
    final up = places > 0;
    final colour = up ? Palette.green : const Color(0xFFB4533C);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: Semantics(
        label: context.t(up ? 'moved_up' : 'moved_down', {'n': places.abs()}),
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: colour),
            Text('${places.abs()}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colour)),
          ],
        ),
      ),
    );
  }
}

/// The group's weekly goal with how far the members have come together.
class _GroupGoal extends StatelessWidget {
  const _GroupGoal({required this.goal, required this.total, required this.owner, required this.onSet});

  final int goal;
  final int total;
  final bool owner;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    if (goal <= 0 && !owner) {
      return const SizedBox.shrink();
    }
    final reached = goal > 0 && total >= goal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    goal > 0 ? context.t('group_goal_progress', {'total': whole(total), 'goal': whole(goal)}) : context.t('group_goal_none'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.ink),
                  ),
                ),
                if (owner)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: onSet,
                    child: Text(context.t(goal > 0 ? 'group_goal_change' : 'group_goal_set'), style: TextStyle(fontSize: 12.5, color: Palette.green, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            if (goal > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (total / goal).clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, _) => LinearProgressIndicator(value: value, minHeight: 7, backgroundColor: Palette.canvas),
                ),
              ),
              if (reached) ...[
                const SizedBox(height: 6),
                Text(context.t('group_goal_reached'), style: TextStyle(fontSize: 12, color: Palette.green, fontWeight: FontWeight.w600)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class GroupBoardScreen extends StatefulWidget {
  const GroupBoardScreen({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  State<GroupBoardScreen> createState() => _GroupBoardScreenState();
}

class _GroupBoardScreenState extends State<GroupBoardScreen> {
  String _week = 'current';
  Map<String, dynamic>? _board;
  Object? _error;
  late int _goal = (widget.group['weekly_goal'] as num?)?.toInt() ?? 0;

  /// The group owner sets how much dhikr the group aims for together each week. 0 removes the goal.
  Future<void> _setGoal() async {
    final field = TextEditingController(text: _goal > 0 ? '$_goal' : '');
    final value = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.t('group_goal_title')),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(counterText: '', helperText: context.t('group_goal_help')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(context.t('cancel'))),
          TextButton(onPressed: () => Navigator.of(dialog).pop(int.tryParse(field.text.trim()) ?? 0), child: Text(context.t('save'))),
        ],
      ),
    );
    field.dispose();
    if (value == null || !mounted) {
      return;
    }
    try {
      final data = Map<String, dynamic>.from(await AppScope.read(context).api.post('dhikr/groups/${widget.group['id']}/goal', body: {'weekly_goal': value}, auth: true) as Map);
      if (mounted) {
        setState(() => _goal = (data['weekly_goal'] as num?)?.toInt() ?? 0);
      }
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// [keep] leaves the current board on screen while a pull down reload runs.
  Future<void> _load({bool keep = false}) async {
    setState(() {
      if (!keep) {
        _board = null;
      }
      _error = null;
    });
    try {
      final data = await AppScope.read(context).api.get('dhikr/groups/${widget.group['id']}/board', auth: true, query: {'week': _week});
      if (mounted) {
        setState(() => _board = Map<String, dynamic>.from(data as Map));
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: PullRefresh(
            onRefresh: () => _load(keep: true),
            child: ListView(
              padding: Layout.page(context, top: 8, bottom: 28),
              children: [
                Row(children: [RoundButton(icon: Icons.arrow_back_rounded, label: context.t('back'), onTap: () => Navigator.of(context).maybePop())]),
                const SizedBox(height: 12),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: DisplayTitle(widget.group['name'].toString(), second: context.t('dhikr_boards'), size: 30)),
                const SizedBox(height: 12),
                const _Intention(),
                const SizedBox(height: 10),
                Segmented<String>(
                  options: [('current', context.t('this_week')), ('last', context.t('last_week'))],
                  value: _week,
                  onChanged: (value) {
                    setState(() => _week = value);
                    unawaited(_load());
                  },
                ),
                const SizedBox(height: 10),
                if (_board == null)
                  LoadView(error: _error, onRetry: _load)
                else ...[
                  if (_week == 'current')
                    _GroupGoal(
                      goal: _goal,
                      total: (_board!['group_total'] as num?)?.toInt() ?? 0,
                      owner: widget.group['owner'] == true,
                      onSet: _setGoal,
                    ),
                  BoardList(rows: [for (final row in (_board!['rows'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
