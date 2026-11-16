import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'core/api.dart';
import 'core/format.dart';
import 'core/lamp.dart';
import 'core/layout.dart';
import 'core/payments.dart';
import 'core/scope.dart';
import 'core/shield.dart';
import 'core/strings.dart';
import 'screens/auth_screens.dart';
import 'screens/dhikr_screen.dart';
import 'screens/gift_status_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/listen_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/support_screen.dart';
import 'theme.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/player_bar.dart';
import 'widgets/ui.dart';

class IqraaApp extends StatefulWidget {
  const IqraaApp({super.key, required this.services});

  final AppServices services;

  @override
  State<IqraaApp> createState() => _IqraaAppState();
}

class _IqraaAppState extends State<IqraaApp> with WidgetsBindingObserver {
  final AppLinks _links = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  String _storeUrl = '';
  bool _updateRequired = false;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    services.prefs.addListener(_applyLook);
    unawaited(_checkVersion());
    unawaited(services.reminders.schedule(services.prefs.language));
    unawaited(services.rivals.sync());
    unawaited(Lamp.refresh(services.cache, services.prefs.language));
    unawaited(_listenForReturns());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    services.prefs.removeListener(_applyLook);
    unawaited(_linkSub?.cancel());
    super.dispose();
  }

  /// Switches between the light and dark looks when the reader picks one or the phone changes its own.
  /// Colours are read as each screen draws, so every screen is asked to draw again, keeping the page the
  /// reader is on.
  void _applyLook() {
    final dark = services.prefs.wantsDark(WidgetsBinding.instance.platformDispatcher.platformBrightness);
    if (dark == Palette.dark) {
      return;
    }
    Palette.dark = dark;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(WidgetsBinding.instance.reassembleApplication()));
  }

  @override
  void didChangePlatformBrightness() => _applyLook();

  /// Locks the account after five minutes away when fingerprint or face unlock is on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = services.session;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      session.backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(services.reminders.stopAdhan());
      unawaited(services.reminders.schedule(services.prefs.language));
      unawaited(services.rivals.sync());
      unawaited(Lamp.refresh(services.cache, services.prefs.language));
      final away = session.backgroundedAt;
      session.backgroundedAt = null;
      if (away != null && DateTime.now().difference(away) > AppConfig.lockAfter) {
        session.lock();
      }
    }
  }

  /// The thank you page sends the reader back with iqraa://donation/REF, which opens that gift's status.
  Future<void> _listenForReturns() async {
    _linkSub = _links.uriLinkStream.listen(_openLink, onError: (Object _) {});
    final initial = await _links.getInitialLink();
    if (initial != null) {
      _openLink(initial);
    }
  }

  void _openLink(Uri uri) {
    final invite = Payments.inviteFrom(uri);
    if (invite != null) {
      _openInvite(invite);
      return;
    }
    final reference = Payments.referenceFrom(uri);
    if (reference == null || !services.session.signedIn) {
      return;
    }
    unawaited(Payments.closeSecurePage());
    final navigator = services.navigatorKey.currentState;
    navigator?.popUntil((route) => route.isFirst);
    navigator?.push(MaterialPageRoute<void>(builder: (_) => GiftStatusScreen(reference: reference)));
  }

  Future<void> _checkVersion() async {
    try {
      final config = await widget.services.cache.load('config');
      widget.services.config = config;
      widget.services.api.audioHosts = {for (final host in (config['audio_hosts'] as List? ?? const [])) host.toString()};
      widget.services.giving.value = config['giving'] == true;
      final platform = Map<String, dynamic>.from((config[Platform.isIOS ? 'ios' : 'android'] ?? const {}) as Map);
      final info = await PackageInfo.fromPlatform();
      final minimum = (platform['min_version'] ?? '').toString();
      if (minimum.isNotEmpty && isOlder(info.version, minimum) && mounted) {
        setState(() {
          _storeUrl = (platform['store_url'] ?? '').toString();
          _updateRequired = true;
        });
      }
    } on ApiException {
      return;
    }
  }

  /// Group invite links join the group, or ask the reader to sign in first and join right after.
  void _openInvite(String code) {
    final navigator = services.navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    navigator.popUntil((route) => route.isFirst);
    if (services.session.signedIn) {
      unawaited(joinGroup(navigator, services, code));
      return;
    }
    services.pendingInvite = code;
    showMessage(navigator.context, navigator.context.t('sign_in_to_join'));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const SignInScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: ListenableBuilder(
        listenable: widget.services.prefs,
        builder: (context, _) => MaterialApp(
        title: 'Iqraa',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        locale: Locale(widget.services.prefs.language),
        supportedLocales: const [Locale('en'), Locale('sw'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorKey: widget.services.navigatorKey,
        scaffoldMessengerKey: widget.services.messengerKey,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final tiny = media.size.width < 360 || media.size.height < 420;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            // Status bar icons stay readable on the light and the dark look.
            value: Palette.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: ColoredBox(
              color: Palette.canvas,
              // On dual screen and folding phones the app keeps to one side of the hinge or fold.
              child: DisplayFeatureSubScreen(
                child: MediaQuery(
                  data: media.copyWith(textScaler: media.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: tiny ? 1.1 : 1.3)),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          );
        },
        home: ValueListenableBuilder<String?>(
          valueListenable: Shield.blocked,
          builder: (context, blocked, _) {
            if (blocked != null) {
              return BlockedScreen(reason: blocked);
            }
            if (_updateRequired) {
              return UpdateScreen(storeUrl: _storeUrl);
            }
            if (AppScope.of(context).session.locked) {
              return const LockScreen();
            }
            return const Shell();
          },
        ),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static const _library = 1;
  static const _listen = 2;
  static const _dhikr = 3;

  int _index = 0;
  final FocusNode _searchFocus = FocusNode();
  final ValueNotifier<int> _dhikrAgain = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => onboardIfNew(context));
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _dhikrAgain.dispose();
    super.dispose();
  }

  void _go(int index) {
    // Tapping the Dhikr tab while already on it goes back to the adhkar at the top.
    if (index == _index && index == _dhikr) {
      _dhikrAgain.value++;
      return;
    }
    setState(() => _index = index);
  }

  void _search() {
    _go(_library);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    final giving = AppScope.of(context).giving.value;
    final pages = [
      HomeScreen(onSearch: _search, onLibrary: () => _go(_library), onListen: () => _go(_listen)),
      LibraryScreen(searchFocus: _searchFocus),
      const ListenScreen(),
      DhikrScreen(reselect: _dhikrAgain),
      if (giving) const SupportScreen(),
    ];
    final items = [
      TabItem(Icons.home_outlined, context.t('tab_home')),
      TabItem(Icons.menu_book_outlined, context.t('tab_library')),
      TabItem(Icons.headphones_outlined, context.t('tab_listen')),
      TabItem(Icons.blur_circular_outlined, context.t('tab_dhikr')),
      if (giving) TabItem(Icons.favorite_border_rounded, context.t('tab_support')),
    ];
    // The Support tab is last, so hiding it never moves the other tabs.
    final index = _index < pages.length ? _index : 0;
    final narration = AppScope.of(context).narration;
    final rail = Layout.useRail(context);
    final stack = IndexedStack(index: index, children: pages);
    // The small player follows the reader across tabs. The Listen tab has its own full player.
    final content = narration.chapter == null || index == _listen
        ? stack
        : Column(
            children: [
              Expanded(child: stack),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, rail ? 10 : 30),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Layout.readable),
                  child: PlayerBar(
                    closable: true,
                    onOpen: () {
                      final chapter = narration.chapter;
                      if (chapter != null) {
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(chapterId: chapter['id'].toString(), bookTitle: narration.bookTitle)));
                      }
                    },
                  ),
                ),
              ),
            ],
          );
    if (rail) {
      return Scaffold(
        body: PatternBackground(
          child: SafeArea(
            child: Row(
              children: [
                SideRail(items: items, index: index, onTap: _go),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: PatternBackground(child: SafeArea(bottom: false, child: content)),
      bottomNavigationBar: BottomBar(index: index, onTap: _go, items: items),
    );
  }
}

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key, required this.storeUrl});

  final String storeUrl;

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
                  DisplayTitle(context.t('update_a'), second: context.t('update_b')),
                  const SizedBox(height: 12),
                  Text(context.t('update_body')),
                  const SizedBox(height: 20),
                  BusyButton(
                    label: context.t('update_button'),
                    onPressed: storeUrl.isEmpty ? null : () async => launchUrl(Uri.parse(storeUrl), mode: LaunchMode.externalApplication),
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
