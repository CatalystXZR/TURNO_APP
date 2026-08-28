import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../services/review_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/review_dialog.dart';

class ArrivalScreen extends ConsumerStatefulWidget {
  final String? bookingId;

  const ArrivalScreen({super.key, this.bookingId});

  @override
  ConsumerState<ArrivalScreen> createState() => _ArrivalScreenState();
}

class _ArrivalScreenState extends ConsumerState<ArrivalScreen> {
  final _reviewService = ReviewService();
  bool _reviewSubmitted = false;
  bool _submitting = false;

  Future<void> _submitReview(int stars, String? comment) async {
    if (_reviewSubmitted || _submitting) return;
    if (widget.bookingId == null) return;
    setState(() => _submitting = true);
    try {
      await _reviewService.submitReview(
        bookingId: widget.bookingId!,
        stars: stars,
        comment: comment,
      );
      if (!mounted) return;
      setState(() => _reviewSubmitted = true);
      AppSnackbar.show(context, 'Resena publicada correctamente.');
    } catch (_) {
      if (!mounted) return;
      AppSnackbar.show(context, 'No pudimos publicar la resena.', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _promptReview() async {
    if (_reviewSubmitted || widget.bookingId == null) return;
    final already = await _reviewService.hasReviewForBooking(widget.bookingId!);
    if (!mounted) return;
    if (already) {
      setState(() => _reviewSubmitted = true);
      return;
    }
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const ReviewDialog(
        title: 'Calificar conductor',
        subtitle: 'Tu referencia sera publica para ayudar a otros pasajeros.',
        confirmLabel: 'Publicar resena',
      ),
    );
    if (result == null || !mounted) return;
    await _submitReview(
      (result['stars'] as int?) ?? 5,
      (result['comment'] as String?)?.trim(),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptReview());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Llegaste a destino',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'El viaje ha finalizado con exito.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              if (_submitting) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
              if (widget.bookingId != null && !_reviewSubmitted && !_submitting) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _promptReview,
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Calificar conductor'),
                ),
              ],
              if (_reviewSubmitted) ...[
                const SizedBox(height: 16),
                Text(
                  'Gracias por tu resena',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Volver al inicio',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
