/**
 * Project: Turno
 *
 * Project Owners: Cristobal Cordova, Carlos Ibarra, Agustin Puelma
 * Software Architecture & Code: Matias Toledo (@catalystxzr)
 *
 * Description: In-app Fintoc checkout via WKWebView. Keeps the payment flow
 * inside the app and intercepts the success/cancel redirect URLs so the user
 * returns to the app automatically when the payment finishes or is interrupted.
 *
 * Copyright (c) 2026 Turno. All rights reserved.
 * This software is proprietary and confidential.
 */

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme.dart';

class FintocCheckoutScreen extends StatefulWidget {
  const FintocCheckoutScreen({super.key, required this.initialUrl});

  final String initialUrl;

  @override
  State<FintocCheckoutScreen> createState() => _FintocCheckoutScreenState();
}

class _FintocCheckoutScreenState extends State<FintocCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final result = _topupResultForUrl(request.url);
            if (result != null) {
              Navigator.of(context).pop(result);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  /// Returns 'success' or 'failure' when the URL is the app's top-up return
  /// link, so the checkout closes itself and the app resumes the flow.
  String? _topupResultForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final isWalletLink = uri.host == 'wallet' || uri.path.contains('/wallet');
    if (!isWalletLink) return null;
    final topup = uri.queryParameters['topup'];
    if (topup == 'success' || topup == 'failure') return topup;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.onSurface,
        elevation: 0,
        title: const Text('Pago seguro con Fintoc'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
