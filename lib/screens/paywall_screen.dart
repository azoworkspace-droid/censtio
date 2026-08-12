import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/entitlement_provider.dart';
import '../services/analytics_service.dart';
import '../services/revenuecat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_brand_icon.dart';
import '../widgets/glass_card.dart';

/// The premium upgrade paywall for RevenueCat-managed products.
enum PaywallReason { freeLimit, proFeature }

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.reason = PaywallReason.proFeature});

  final PaywallReason reason;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────

  Package? _selectedPackage;
  bool _isLoading = false;
  bool _isFetchingOffering = true;
  String? _errorMessage;

  late final AnimationController _shimmerController;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.track('pro_paywall_viewed'));
    unawaited(AnalyticsService.track('paywall_viewed'));
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _fetchOffering();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  // ── Data fetching ──────────────────────────────────────────────────────────

  Future<void> _fetchOffering() async {
    setState(() => _isFetchingOffering = true);
    if (!RevenueCatService.isConfigured) {
      if (!mounted) return;
      setState(() {
        _isFetchingOffering = false;
        _errorMessage =
            'Subscriptions are unavailable in this development build.';
      });
      return;
    }
    try {
      final offering = await RevenueCatService.getCurrentOffering().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (!mounted) return;
      setState(() {
        // Prefer the monthly package for the primary launch plan. Fall back
        // to the first configured package only if RevenueCat has no monthly
        // package yet (for example while an annual plan is still configured).
        _selectedPackage =
            offering?.monthly ?? offering?.availablePackages.firstOrNull;
        _isFetchingOffering = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFetchingOffering = false;
      });
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _subscribe() async {
    if (_selectedPackage == null) {
      setState(() {
        _errorMessage =
            'No subscription package available. Please try again later.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final bool success = await ref
          .read(purchaseActionsProvider)
          .subscribe(_selectedPackage!);
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (success) {
        unawaited(AnalyticsService.track('subscription_started'));
        _showSuccessAndPop();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        setState(() => _errorMessage = 'Purchase failed: ${e.message}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final bool success = await ref.read(purchaseActionsProvider).restore();
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (success) {
        _showSuccessAndPop();
      } else {
        setState(
          () => _errorMessage = 'No prior purchases found for this Apple ID.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Restore failed. Please try again.';
      });
    }
  }

  void _showSuccessAndPop() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.emerald,
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppTheme.bgDeep),
            const SizedBox(width: 10),
            Text(
              'Welcome to Centsio Pro! All features unlocked.',
              style: AppTheme.bodyMedium(color: AppTheme.bgDeep),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
    Navigator.of(context).pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Stack(
        children: [
          const _BackgroundDecoration(),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildTopBar(),
                      const SizedBox(height: 16),
                      _buildHero(),
                      const SizedBox(height: 36),
                      _buildFeatureList(),
                      const SizedBox(height: 32),
                      _buildPricingCard(),
                      const SizedBox(height: 28),
                      _buildCTA(),
                      const SizedBox(height: 16),
                      _buildRestoreButton(),
                      const SizedBox(height: 12),
                      _buildLegalFooter(),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          // Full-screen loading overlay
          if (_isLoading) const _LoadingOverlay(),
        ],
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            icon: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: AppTheme.textSecondary,
                size: 20,
              ),
            ),
          ),
          const Spacer(),
          // "PRO" badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              gradient: AppTheme.emeraldGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: AppTheme.emeraldGlow, blurRadius: 12),
              ],
            ),
            child: Text(
              '⚡ PRO',
              style: AppTheme.labelSmall(color: AppTheme.bgDeep),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final isFreeLimit = widget.reason == PaywallReason.freeLimit;

    return Column(
      children: [
        const AppBrandIcon(size: 88, borderRadius: 24),
        const SizedBox(height: 24),
        Text(
          isFreeLimit ? 'You’ve reached your free limit' : 'Unlock Centsio Pro',
          style: AppTheme.headlineMedium(),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            isFreeLimit
                ? 'You used the 3 free creations included this month. Upgrade to keep creating without interruption.'
                : 'Create professional invoices, quotes, and expenses without limits.',
            style: AppTheme.bodyMedium(),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureList() {
    const features = [
      _FeatureData(
        icon: Icons.image_outlined,
        title: 'Custom Logo Branding',
        subtitle: 'Upload your business logo to personalize every PDF invoice.',
        freeTier: 'Standard tile',
        proTier: 'Custom logo',
      ),
      _FeatureData(
        icon: Icons.cleaning_services_outlined,
        title: 'Remove Watermark',
        subtitle: 'Clean, unbranded invoices ready for enterprise clients.',
        freeTier: 'Watermarked',
        proTier: 'Clean PDF',
      ),
      _FeatureData(
        icon: Icons.all_inclusive_rounded,
        title: 'Unlimited Invoices, Quotes & Expenses',
        subtitle:
            'Create as many business records as you need — no monthly cap.',
        freeTier: '3 combined / month',
        proTier: 'Unlimited',
      ),
      _FeatureData(
        icon: Icons.bar_chart_rounded,
        title: 'Tax Reports & Analytics',
        subtitle:
            'Full profit/loss breakdown, quarterly summaries, and export.',
        freeTier: 'Basic dashboard',
        proTier: 'Full reports',
      ),
    ];

    return Column(
      children: features.map((f) => _FeatureTile(data: f)).toList(),
    );
  }

  Widget _buildPricingCard() {
    if (_isFetchingOffering) {
      return GlassCard(
        child: SizedBox(
          height: 96,
          child: Center(
            child: CircularProgressIndicator(
              color: AppTheme.emerald,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    // No package available — show a gentle notice rather than a fake price
    if (_selectedPackage == null) {
      return GlassCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: AppTheme.textSecondary,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              'Subscription unavailable',
              style: AppTheme.bodyLarge(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Could not load pricing from the App Store. Please check your connection and try again.',
              style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _fetchOffering,
              icon: const Icon(
                Icons.refresh_rounded,
                color: AppTheme.emerald,
                size: 18,
              ),
              label: Text(
                'Retry',
                style: AppTheme.bodyMedium(color: AppTheme.emerald),
              ),
            ),
          ],
        ),
      );
    }

    final product = _selectedPackage!.storeProduct;
    final priceString = product.priceString;
    final title = product.title.isNotEmpty ? product.title : 'Centsio Pro';
    final subtitle = product.description.isNotEmpty
        ? product.description
        : 'Everything you need to run your business';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: [
          BoxShadow(
            color: AppTheme.emerald.withAlpha(40),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: GlassCard(
        padding: const EdgeInsets.all(24),
        border: Border.all(color: AppTheme.emerald, width: 1.5),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(title, style: AppTheme.titleLarge()),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppTheme.emeraldGradient,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.emeraldGlow,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              _packageBadge(_selectedPackage!),
                              style: AppTheme.labelSmall(
                                color: AppTheme.bgDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTheme.bodyMedium(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      priceString,
                      style: AppTheme.titleLarge(color: AppTheme.emerald),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _packagePeriodLabel(_selectedPackage!),
                      style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCTA() {
    // If no package is available, disable the button
    final bool canPurchase = _selectedPackage != null && !_isLoading;
    final String priceLabel = _selectedPackage != null
        ? 'Start Centsio Pro — ${_selectedPackage!.storeProduct.priceString}/${_packagePeriodShortLabel(_selectedPackage!)}'
        : 'Start Centsio Pro';

    return Column(
      children: [
        if (_errorMessage != null) ...[
          Text(
            _errorMessage!,
            style: AppTheme.bodyMedium(color: AppTheme.errorRed),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
        GestureDetector(
          onTap: canPurchase ? _subscribe : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 58,
            decoration: BoxDecoration(
              gradient: canPurchase
                  ? AppTheme.emeraldGradient
                  : LinearGradient(
                      colors: [AppTheme.bgSurface, AppTheme.bgSurface],
                    ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              boxShadow: canPurchase
                  ? [
                      BoxShadow(
                        color: AppTheme.emeraldGlow,
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.star_rounded,
                  color: canPurchase ? AppTheme.bgDeep : AppTheme.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  priceLabel,
                  style: AppTheme.titleLarge(
                    color: canPurchase
                        ? AppTheme.bgDeep
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRestoreButton() {
    return Center(
      child: TextButton(
        onPressed: _isLoading ? null : _restore,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          'Restore Purchases',
          style: AppTheme.bodyMedium(color: AppTheme.emerald),
        ),
      ),
    );
  }

  Widget _buildLegalFooter() {
    return Column(
      children: [
        Text(
          'Subscription auto-renews ${_selectedPackage == null ? 'automatically' : _packagePeriodLabel(_selectedPackage!)}. Cancel anytime '
          'in your iPhone Settings → Apple ID → Subscriptions.',
          style: AppTheme.labelSmall(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegalLink(
              label: 'Terms of Use',
              url: 'https://freelancerapp.com/terms',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '·',
                style: AppTheme.labelSmall(color: AppTheme.textSecondary),
              ),
            ),
            _LegalLink(
              label: 'Privacy Policy',
              url: 'https://centsioai.blogspot.com/2026/08/centsioaiprivacypremium.html',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          Platform.isIOS
              ? 'Payment will be charged to your Apple ID account at confirmation of purchase.'
              : '',
          style: AppTheme.labelSmall(color: AppTheme.textHint),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _packageBadge(Package package) {
    return switch (package.packageType) {
      PackageType.monthly => 'MONTHLY',
      PackageType.annual => 'ANNUAL',
      PackageType.weekly => 'WEEKLY',
      _ => 'PRO',
    };
  }

  String _packagePeriodLabel(Package package) {
    return switch (package.packageType) {
      PackageType.monthly => 'per month',
      PackageType.annual => 'per year',
      PackageType.weekly => 'per week',
      PackageType.sixMonth => 'per 6 months',
      PackageType.threeMonth => 'per 3 months',
      PackageType.twoMonth => 'per 2 months',
      _ => 'per period',
    };
  }

  String _packagePeriodShortLabel(Package package) {
    return switch (package.packageType) {
      PackageType.monthly => 'month',
      PackageType.annual => 'year',
      PackageType.weekly => 'week',
      PackageType.sixMonth => '6 months',
      PackageType.threeMonth => '3 months',
      PackageType.twoMonth => '2 months',
      _ => 'period',
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Legal link button
// ══════════════════════════════════════════════════════════════════════════════

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Text(
        label,
        style: AppTheme.labelSmall(color: AppTheme.electricBlue).copyWith(
          decoration: TextDecoration.underline,
          decorationColor: AppTheme.electricBlue,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Feature tile
// ══════════════════════════════════════════════════════════════════════════════

class _FeatureData {
  const _FeatureData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.freeTier,
    required this.proTier,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String freeTier;
  final String proTier;
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.data});
  final _FeatureData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.emerald.withAlpha(18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.emerald.withAlpha(40)),
              ),
              child: Icon(data.icon, color: AppTheme.emerald, size: 22),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.title, style: AppTheme.bodyLarge()),
                  const SizedBox(height: 2),
                  Text(data.subtitle, style: AppTheme.bodyMedium()),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Free → Pro column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Pill(label: data.freeTier, isGrey: true),
                const SizedBox(height: 4),
                _Pill(label: data.proTier, isGrey: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.isGrey});
  final String label;
  final bool isGrey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGrey
            ? Colors.white.withAlpha(12)
            : AppTheme.emerald.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isGrey ? AppTheme.glassBorder : AppTheme.emerald.withAlpha(60),
        ),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall(
          color: isGrey ? AppTheme.textHint : AppTheme.emerald,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Decorative background
// ══════════════════════════════════════════════════════════════════════════════

class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SizedBox.expand(
      child: Stack(
        children: [
          // Large emerald orb — centre top
          Positioned(
            top: -size.width * 0.4,
            left: size.width * 0.1,
            child: _Orb(
              size: size.width * 0.8,
              color: AppTheme.emerald.withAlpha(16),
            ),
          ),
          // Small purple orb — bottom left
          Positioned(
            bottom: size.height * 0.05,
            left: -size.width * 0.2,
            child: _Orb(
              size: size.width * 0.55,
              color: const Color(0xFF6C63FF).withAlpha(14),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, Colors.transparent]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Loading overlay
// ══════════════════════════════════════════════════════════════════════════════

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(160),
      child: Center(
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: AppTheme.emerald,
                  strokeWidth: 2.5,
                ),
              ),
              const SizedBox(height: 16),
              Text('Processing…', style: AppTheme.bodyLarge()),
              const SizedBox(height: 4),
              Text('Please wait', style: AppTheme.bodyMedium()),
            ],
          ),
        ),
      ),
    );
  }
}
