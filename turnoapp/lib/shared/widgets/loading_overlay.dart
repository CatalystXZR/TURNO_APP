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

import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x9916212B),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Card(
                    color: const Color(0xFFFCFDFF),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 22,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(strokeWidth: 3),
                          if (message != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
