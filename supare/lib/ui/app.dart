import 'package:flutter/material.dart';
import '../core/app_store.dart';
import 'tasks.dart';
import 'wallet.dart';
import 'settings.dart';

class SupareApp extends StatefulWidget {
  const SupareApp({super.key, required this.store});
  final AppStore store;
  @override
  State<SupareApp> createState() => _SupareAppState();
}

class _SupareAppState extends State<SupareApp> with WidgetsBindingObserver {
  int tab = 0;
  int walletGeneration = 0;
  bool privacyCover = false;
  String? resumeError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => reconcile());
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> reconcile() async {
    try {
      await cleanWalletTemporaryFiles();
      // AppStore reconciles persisted native actions, then refreshes schedules.
      await widget.store.reconcileNativeActions();
      await widget.store.rescheduleAlarms();
      if (mounted) setState(() => resumeError = widget.store.lastAlarmError);
    } catch (_) {
      if (mounted) {
        setState(
          () => resumeError =
              'Some reminders could not be refreshed. Check alarm access in Settings.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (state == AppLifecycleState.paused) widget.store.auth.lock();
      if (mounted) {
        setState(() {
          privacyCover = true;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => privacyCover = false);
      reconcile();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.store.settings['theme'] ?? 'system';
    return MaterialApp(
      title: 'Supare',
      debugShowCheckedModeBanner: false,
      themeMode: mode == 'dark'
          ? ThemeMode.dark
          : mode == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Builder(
        builder: (context) => Stack(
          children: [
            Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    if (resumeError != null)
                      MaterialBanner(
                        content: Text(resumeError!),
                        actions: [
                          TextButton(
                            onPressed: () => setState(() => tab = 3),
                            child: const Text('Settings'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => resumeError = null),
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: switch (tab) {
                        0 => TasksScreen(store: widget.store, upcoming: false),
                        1 => TasksScreen(store: widget.store, upcoming: true),
                        2 => WalletScreen(
                          key: ValueKey(walletGeneration),
                          store: widget.store,
                        ),
                        _ => SettingsScreen(store: widget.store),
                      },
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (value) async {
                  if (tab == 2 && value != 2) {
                    widget.store.auth.lock();
                    await widget.store.native.setSecure(false);
                  }
                  if (value == 2) await widget.store.native.setSecure(true);
                  if (mounted) setState(() => tab = value);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.today_outlined),
                    selectedIcon: Icon(Icons.today),
                    label: 'Today',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.date_range_outlined),
                    selectedIcon: Icon(Icons.date_range),
                    label: 'Upcoming',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.folder_outlined),
                    selectedIcon: Icon(Icons.folder),
                    label: 'Wallet',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tune_outlined),
                    selectedIcon: Icon(Icons.tune),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
            if (privacyCover)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0xff123e35),
                  child: Center(
                    child: Icon(
                      Icons.lock_outline,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff226b53),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: dark
          ? const Color(0xff111a17)
          : const Color(0xfff7f8f4),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff202c26) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xff202c26) : Colors.white,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xff18231e) : Colors.white,
        indicatorColor: scheme.primaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(fontFamily: 'sans-serif'),
    );
  }
}
