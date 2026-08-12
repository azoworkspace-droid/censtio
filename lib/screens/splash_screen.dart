import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_brand_icon.dart';

/// Branded startup screen shown while local settings and services initialize.
class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    this.progress = 0,
    this.status = 'Starting securely…',
    this.error,
    this.onRetry,
  });

  final double progress;
  final String status;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    final safeProgress = progress.clamp(0.0, 1.0).toDouble();

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppBrandIcon(size: 96, borderRadius: 26),
                const SizedBox(height: 24),
                Text(
                  'Centsio AI: Invoice Maker',
                  style: AppTheme.displayLarge().copyWith(fontSize: 30),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Text(
                  'AI invoices & expense manager',
                  style: AppTheme.bodyLarge(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 44),
                if (hasError) ...[
                  Text(
                    'Startup could not finish',
                    style: AppTheme.titleLarge(color: AppTheme.errorRed),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ] else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: safeProgress,
                      minHeight: 7,
                      backgroundColor: AppTheme.glassBorder,
                      valueColor: const AlwaysStoppedAnimation(
                        AppTheme.emerald,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    status,
                    style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(safeProgress * 100).round()}%',
                    style: AppTheme.labelSmall(color: AppTheme.emerald),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
