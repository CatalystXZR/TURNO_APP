/**
 * Project: Turno
 * 
 * Project Owners: Cristobal Cordova, Carlos Ibarra, Agustin Puelma
 * Software Architecture & Code: Matias Toledo (@catalystxzr)
 * 
 * Description: Production-grade implementation for UDD carpooling system.
 * 
 * Copyright (c) 2026 Turno. All rights reserved.
 * This software is proprietary and confidential.
 */

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../models/transaction.dart';
import '../../providers/home_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/decorative_background.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'fintoc_checkout_screen.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  bool _operationInProgress = false;
  bool _shouldPopAfterWithdrawal = false;

  StreamSubscription<Uri>? _topupLinkSub;
  static String? _lastHandledTopupLink;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _topupLinkSub = AppLinks().uriLinkStream.listen(_handleTopupReturn);
    _handleInitialTopupLink();
    Future.microtask(() => ref.read(walletProvider.notifier).load());
  }

  @override
  void dispose() {
    _topupLinkSub?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleInitialTopupLink() async {
    try {
      final initial = await AppLinks().getInitialLink();
      if (initial != null) {
        _handleTopupReturn(initial);
      }
    } catch (e) {
      debugPrint('[Turno] Wallet: initial link error: $e');
    }
  }

  void _handleTopupReturn(Uri uri) {
    // iOS: turnoapp://wallet?topup=success -> host == 'wallet'
    // Web: https://turnoapp.cl/wallet?topup=success -> path == /wallet
    final isWalletLink = uri.host == 'wallet' || uri.path.contains('/wallet');
    if (!isWalletLink) return;
    final result = uri.queryParameters['topup'];
    if (result == null) return;
    if (_lastHandledTopupLink == uri.toString()) return;
    _lastHandledTopupLink = uri.toString();
    _showTopupResult(result);
  }

  void _showTopupResult(String? result) {
    if (!mounted) return;
    if (result == 'success') {
      AppSnackbar.show(context, 'Recarga completada. Tu saldo ya esta disponible.');
    } else if (result == 'failure') {
      AppSnackbar.show(
        context,
        'El pago fue cancelado o no se completo. Intentalo nuevamente.',
        isError: true,
      );
    }
    _load();
  }

  Future<void> _load() async {
    try {
      await ref.read(walletProvider.notifier).load();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos cargar tu billetera.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _startTopup() async {
    if (_operationInProgress) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Selecciona monto a recargar',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pagas de forma segura a traves de Fintoc (bancos y tarjetas).',
              style: TextStyle(color: AppTheme.subtle, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: AppConstants.quickTopupAmountsCLP.map((amount) {
                final fmt = NumberFormat.currency(
                  locale: 'es_CL',
                  symbol: '\$',
                  decimalDigits: 0,
                ).format(amount);
                return ActionChip(
                  side: const BorderSide(color: Color(0xFFD6E1EA)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  label: Text(fmt),
                  onPressed: () => Navigator.pop(ctx, amount),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    final fee = AppConstants.topupFeeForAmount(selected);
    final charged = AppConstants.topupChargedAmount(selected);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar recarga'),
        content: Text(
          'Se cargaran \$$charged a tu medio de pago '
          '(incluye \$$fee de comision). '
          'Se abrira Fintoc dentro de la app para completar el pago.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pagar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _operationInProgress = true;
    try {
      final redirectUrl =
          await ref.read(walletProvider.notifier).createTopupIntent(selected);
      if (!mounted) return;
      final uri = Uri.tryParse(redirectUrl);
      if (uri == null) {
        throw Exception('payment_provider_error');
      }
      if (kIsWeb) {
        // webview_flutter has no web implementation: open Fintoc in a new tab
        // and rely on the AppLinks stream to catch the return URL.
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          throw Exception('payment_provider_error');
        }
      } else {
        final result = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => FintocCheckoutScreen(initialUrl: uri.toString()),
          ),
        );
        if (!mounted) return;
        _showTopupResult(result);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos iniciar el pago. Intenta nuevamente.',
        ),
        isError: true,
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _requestWithdrawal() async {
    if (_operationInProgress) return;
    final balance = ref.read(walletProvider).wallet?.balanceAvailable ?? 0;
    if (balance < AppConstants.minWithdrawalCLP) {
      AppSnackbar.show(
        context,
        'Necesitas al menos \$${AppConstants.minWithdrawalCLP} para retirar',
        isError: true,
      );
      return;
    }

    final amountController = TextEditingController(text: balance.toString());
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solicitar retiro'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ingresa el monto a retirar (min. \$${AppConstants.minWithdrawalCLP}, max. \$$balance).',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monto (CLP)',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'Ingresa un numero valido';
                  if (n < AppConstants.minWithdrawalCLP) {
                    return 'Minimo \$${AppConstants.minWithdrawalCLP}';
                  }
                  if (n > balance) return 'Supera tu saldo disponible';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Modo sandbox: el monto se debitara de tu saldo inmediatamente.',
                style: TextStyle(fontSize: 12, color: AppTheme.subtle),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Solicitar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      amountController.dispose();
      return;
    }

    final amount = int.tryParse(amountController.text.trim()) ?? 0;
    amountController.dispose();

    if (amount <= 0 || amount > balance) return;

    _operationInProgress = true;
    try {
      await ref.read(walletProvider.notifier).sandboxWithdraw(amount);
      if (!mounted) return;
      AppSnackbar.show(context, 'Retiro realizado con exito');
      _shouldPopAfterWithdrawal = true;
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos procesar el retiro.',
        ),
        isError: true,
      );
    } finally {
      _operationInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(walletProvider);
    final wallet = state.wallet;

    if (!state.loading && !_fadeController.isCompleted) {
      _fadeController.forward();
    }

    if (_shouldPopAfterWithdrawal && !state.topupLoading) {
      _shouldPopAfterWithdrawal = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(homeProvider.notifier).refresh();
        Future.microtask(() {
          if (!mounted) return;
          context.pop();
        });
      });
    }

    final balanceFmt = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(wallet?.balanceAvailable ?? 0);

    return LoadingOverlay(
      isLoading: state.topupLoading,
      message: 'Procesando...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Billetera'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
        ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
            : DecorativeBackground(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.gradientDarkStart,
                                AppTheme.gradientDarkMid,
                                AppTheme.gradientDarkEnd,
                              ],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: AppTheme.gradientShadow,
                                blurRadius: 24,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Saldo disponible',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.gradientLabel,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                balanceFmt,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 16),
                               Row(
                                 children: [
                                   Expanded(
                                     child: ElevatedButton.icon(
                                       onPressed: state.topupLoading
                                           ? null
                                           : _startTopup,
                                       style: ElevatedButton.styleFrom(
                                         backgroundColor: Colors.white,
                                         foregroundColor: AppTheme.primary,
                                       ),
                                       icon: const Icon(Icons.add),
                                       label: const Text('Recargar'),
                                     ),
                                   ),
                                   const SizedBox(width: 10),
                                   Expanded(
                                     child: ElevatedButton.icon(
                                       onPressed: state.topupLoading
                                           ? null
                                           : _requestWithdrawal,
                                       style: ElevatedButton.styleFrom(
                                         backgroundColor: Colors.white,
                                         foregroundColor: AppTheme.primary,
                                       ),
                                       icon: const Icon(Icons.arrow_downward),
                                       label: const Text('Retirar'),
                                     ),
                                   ),
                                 ],
                               ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (state.transactions.isNotEmpty) ...[
                          Text(
                            'Historial',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          ...state.transactions
                              .map((tx) => _TransactionTile(tx: tx)),
                        ] else
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'Sin movimientos aun',
                                style: TextStyle(color: AppTheme.subtle),
                              ),
                            ),
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

class _TransactionTile extends StatelessWidget {
  final Transaction tx;

  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final amtFmt = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(tx.amount.abs());
    final dateFmt =
        DateFormat('d MMM, HH:mm', 'es').format(tx.createdAt.toLocal());
    final isCredit = tx.amount > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          backgroundColor:
              isCredit ? const                                 Color(0xE9F6EE) : const Color(0xFFFCEDEF),
          child: Icon(
            isCredit ? Icons.arrow_downward : Icons.arrow_upward,
            color: isCredit ? AppTheme.success : AppTheme.danger,
            size: 18,
          ),
        ),
        title: Text(tx.typeLabel,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          dateFmt,
          style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
        ),
        trailing: Text(
          '${isCredit ? '+' : '-'}$amtFmt',
          style: TextStyle(
            color: isCredit ? AppTheme.success : AppTheme.danger,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
