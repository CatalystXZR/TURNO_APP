import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/lifecycle_provider.dart';
import 'router.dart';
import 'theme.dart';

class Turno extends ConsumerStatefulWidget {
  const Turno({super.key});

  @override
  ConsumerState<Turno> createState() => _TurnoState();
}

class _TurnoState extends ConsumerState<Turno>
    with WidgetsBindingObserver {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _linkSub = AppLinks().uriLinkStream.listen(_handleAppLink);
    _handleInitialLink();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _handleInitialLink() async {
    try {
      final initial = await AppLinks().getInitialLink();
      if (initial != null) {
        _handleAppLink(initial);
      }
    } catch (e) {
      debugPrint('[Turno] Initial link error: $e');
    }
  }

  void _handleAppLink(Uri uri) {
    if (uri.host == 'wallet' || uri.path.contains('/wallet')) {
      appRouter.go('/wallet');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    ref.read(lifecycleStateProvider.notifier).state = state;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Turno',
      theme: AppTheme.light,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
