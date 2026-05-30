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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
