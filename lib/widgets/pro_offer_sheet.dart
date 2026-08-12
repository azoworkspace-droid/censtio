import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/entitlement_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';

/// A floating launch-time Pro offer dialog. It uses StoreKit/RevenueCat prices
/// and never displays hard-coded financial values.
class ProOfferSheet extends ConsumerStatefulWidget {
  const ProOfferSheet({this.offering, super.key});

  final Offering? offering;

  @override
  ConsumerState<ProOfferSheet> createState() => _ProOfferSheetState();
}

class _ProOfferSheetState extends ConsumerState<ProOfferSheet> {
  Package? _selectedPackage;
  bool _isLoading = false;
  String? _errorMessage;

  Package? get _monthly => widget.offering?.monthly;
  Package? get _annual => widget.offering?.annual;

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.track('pro_paywall_viewed'));
    // Annual is selected first because it is the better-value option, while
    // both durations remain equally visible and selectable.
    _selectedPackage = _annual ?? _monthly;
  }

  Future<void> _purchase() async {
    final package = _selectedPackage;
    if (package == null || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await ref
          .read(purchaseActionsProvider)
          .subscribe(package);
      if (!mounted) return;
      if (success) {
        unawaited(AnalyticsService.track('subscription_started'));
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Purchase could not be completed. Please try again.';
        });
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      final code = PurchasesErrorHelper.getErrorCode(error);
      setState(() {
        _isLoading = false;
        _errorMessage = code == PurchasesErrorCode.purchaseCancelledError
            ? null
            : 'Purchase failed. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Purchase failed. Please try again.';
      });
    }
  }

  Future<void> _restore() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await ref.read(purchaseActionsProvider).restore();
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No active Pro subscription was found.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPackages = _monthly != null || _annual != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: AppTheme.bgDeep,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppTheme.glassBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppTheme.emerald.withAlpha(30),
              blurRadius: 36,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: AppTheme.emerald,
                  size: 54,
                ),
                const SizedBox(height: 10),
                Text(
                  'Unlock Centsio Pro',
                  style: AppTheme.displayLarge().copyWith(fontSize: 30),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create without limits and send polished invoices with confidence.',
                  style: AppTheme.bodyLarge(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                _buildFeature('Unlimited invoices, quotes & expenses'),
                _buildFeature('Custom branding and clean PDF exports'),
                _buildFeature('Tax reports and AI-powered tools'),
                const SizedBox(height: 18),
                if (hasPackages) ...[
                  Row(
                    children: [
                      if (_monthly != null)
                        Expanded(child: _buildPlanCard(_monthly!, false)),
                      if (_monthly != null && _annual != null)
                        const SizedBox(width: 10),
                      if (_annual != null)
                        Expanded(child: _buildPlanCard(_annual!, true)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: AppTheme.bodyMedium(color: AppTheme.errorRed),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _purchase,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Start Pro — ${_selectedPackage!.storeProduct.priceString}',
                            ),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Plans are temporarily unavailable. Please try again later.',
                    style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isLoading ? null : _restore,
                  child: const Text('Restore Purchases'),
                ),
                Text(
                  'Subscriptions renew automatically until cancelled. Payment is charged through your App Store account.',
                  style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    _legalLink(
                      'Terms of Use',
                      'https://freelancerapp.com/terms',
                    ),
                    Text('  ·  ', style: AppTheme.labelSmall()),
                    _legalLink(
                      'Privacy Policy',
                      'https://centsioai.blogspot.com/2026/08/centsioaiprivacypremium.html',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.emerald,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: AppTheme.bodyMedium())),
        ],
      ),
    );
  }

  Widget _buildPlanCard(Package package, bool isAnnual) {
    final selected = identical(package, _selectedPackage);
    final product = package.storeProduct;
    return GestureDetector(
      onTap: _isLoading
          ? null
          : () => setState(() => _selectedPackage = package),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.emerald.withValues(alpha: 0.14)
              : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(
            color: selected ? AppTheme.emerald : AppTheme.glassBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isAnnual ? 'Yearly' : 'Monthly',
                    style: AppTheme.bodyLarge(),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppTheme.emerald : AppTheme.textSecondary,
                  size: 19,
                ),
              ],
            ),
            if (isAnnual) ...[
              const SizedBox(height: 4),
              Text(
                'Best value',
                style: AppTheme.labelSmall(color: AppTheme.orange),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              product.priceString,
              style: AppTheme.titleLarge(color: AppTheme.emerald),
            ),
            Text(
              isAnnual ? 'per year' : 'per month',
              style: AppTheme.labelSmall(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legalLink(String label, String url) {
    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Text(
        label,
        style: AppTheme.labelSmall(
          color: AppTheme.electricBlue,
        ).copyWith(decoration: TextDecoration.underline),
      ),
    );
  }
}
