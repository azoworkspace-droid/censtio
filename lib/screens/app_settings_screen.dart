import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/entitlement_provider.dart';
import '../providers/database_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/tax_rate_provider.dart';
import '../screens/settings_screen.dart';
import '../screens/paywall_screen.dart';
import '../services/app_lock_service.dart';
import '../services/revenuecat_service.dart';
import '../services/settings_service.dart';
import 'app_lock_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/app_brand_icon.dart';
import '../widgets/glass_card.dart';

/// Screen for general application preferences, subscription management,
/// invoice defaults, and legal/support links.
class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  static const _appStoreUrl = 'https://apps.apple.com/app/id6799664774';
  static const _appStoreReviewUrl =
      'https://apps.apple.com/app/id6799664774?action=write-review';

  String _selectedLanguage = 'English';
  final _taxRateController = TextEditingController();
  final _notesController = TextEditingController();

  final List<String> _languages = const ['English', 'Français', 'Español'];
  bool _isLoadingDefaults = true;
  bool _appLockEnabled = false;
  AppLockMode _appLockMode = AppLockMode.password;
  bool _securityActionInProgress = false;
  int _securityStateRevision = 0;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final revisionAtStart = _securityStateRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final appLockEnabled = await AppLockService.isEnabled();
      final appLockMode = await AppLockService.getMode();
      final defaultTaxRate = await SettingsService.getDefaultTaxRate();
      if (!mounted) return;
      setState(() {
        _selectedLanguage = prefs.getString('default_language') ?? 'English';
        _taxRateController.text = defaultTaxRate == 0
            ? ''
            : defaultTaxRate.toString();
        _notesController.text = prefs.getString('default_notes') ?? '';
        if (revisionAtStart == _securityStateRevision) {
          _appLockEnabled = appLockEnabled;
          _appLockMode = appLockMode;
        }
        _isLoadingDefaults = false;
      });
    } catch (error, stackTrace) {
      // Settings must remain usable even if a platform storage plugin is
      // temporarily unavailable. Security actions will show their own error.
      debugPrint('Settings defaults failed to load: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _isLoadingDefaults = false);
    }
  }

  Future<void> _toggleAppLock(bool enable) async {
    if (_securityActionInProgress) return;
    _securityStateRevision++;
    setState(() => _securityActionInProgress = true);

    if (enable) {
      try {
        final configured = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const AppLockSetupScreen()),
        );
        if (!mounted || configured != true) return;
        final mode = await AppLockService.getMode();
        if (!mounted) return;
        setState(() {
          _appLockEnabled = true;
          _appLockMode = mode;
        });
        AppLockService.requestLock();
      } finally {
        if (mounted) setState(() => _securityActionInProgress = false);
      }
      return;
    }

    // Require the existing credential before allowing the protection to be
    // disabled. The same screen supports Face ID/Touch ID and password.
    try {
      final verified = await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute(builder: (_) => const AppLockScreen()));
      if (!mounted || verified != true) return;
      await AppLockService.disable();
      if (mounted) {
        setState(() {
          _appLockEnabled = false;
          _appLockMode = AppLockMode.password;
        });
      }
    } finally {
      if (mounted) setState(() => _securityActionInProgress = false);
    }
  }

  Future<void> _changeAppLockMethod() async {
    if (_securityActionInProgress) return;
    if (!_appLockEnabled) {
      await _toggleAppLock(true);
      return;
    }

    _securityStateRevision++;
    setState(() => _securityActionInProgress = true);
    try {
      final configured = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AppLockSetupScreen()),
      );
      if (!mounted || configured != true) return;
      final mode = await AppLockService.getMode();
      if (!mounted) return;
      setState(() => _appLockMode = mode);
      AppLockService.requestLock();
    } finally {
      if (mounted) setState(() => _securityActionInProgress = false);
    }
  }

  Future<void> _saveDefaultLanguage(String lang) async {
    setState(() => _selectedLanguage = lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_language', lang);
  }

  Future<void> _saveDefaultTaxRate(String val) async {
    final parsed = double.tryParse(val.trim());
    final rate = parsed != null && parsed >= 0 && parsed <= 100 ? parsed : 0.0;
    await ref.read(defaultTaxRateProvider.notifier).setTaxRate(rate);
  }

  Future<void> _saveDefaultNotes(String val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_notes', val.trim());
  }

  @override
  void dispose() {
    _taxRateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _launchURL(String urlString) async {
    final Uri uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.errorRed,
              content: Text('Could not launch $urlString'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Launch URL error: $e');
    }
  }

  Future<void> _shareApp() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final shareOrigin = renderBox == null
        ? null
        : renderBox.localToGlobal(Offset.zero) & renderBox.size;

    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Check out Centsio AI: Invoice Maker — create professional invoices and track expenses with AI!\n$_appStoreUrl',
          sharePositionOrigin: shareOrigin,
        ),
      );
    } catch (error) {
      debugPrint('Share app error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.errorRed,
          content: Text('Unable to open the share menu.'),
        ),
      );
    }
  }

  Future<void> _restorePurchases() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppTheme.bgCard,
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: AppTheme.emerald,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 12),
            Text('Restoring purchases...'),
          ],
        ),
      ),
    );

    final info = await RevenueCatService.restorePurchases();
    ref.invalidate(entitlementProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (info != null && info.entitlements.active.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.emerald,
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppTheme.bgDeep),
              const SizedBox(width: 10),
              Text(
                'Purchases restored successfully!',
                style: AppTheme.bodyMedium(color: AppTheme.bgDeep),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.bgCard,
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.warningAmber),
              const SizedBox(width: 10),
              Text(
                'No active subscription found to restore.',
                style: AppTheme.bodyMedium(),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final proAsync = ref.watch(entitlementProvider);
    final isPro = proAsync.value ?? false;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'App Settings',
          style: AppTheme.headlineMedium().copyWith(fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: _isLoadingDefaults
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.emerald,
                  strokeWidth: 2.5,
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // ── SECTION 1: INVOICE DEFAULTS ────────────────────────────
                  _buildProfileLinkCard(),
                  const SizedBox(height: 24),
                  _buildInvoiceDefaultsCard(),
                  const SizedBox(height: 24),

                  _buildDataBackupCard(),
                  const SizedBox(height: 24),

                  // ── SECTION 2: SECURITY ───────────────────────────────────
                  _buildSecurityCard(),
                  const SizedBox(height: 24),

                  // ── SECTION 3: ACCOUNT & PRO ──────────────────────────────
                  _buildAccountProCard(isPro),
                  const SizedBox(height: 24),

                  // ── SECTION 4: SUPPORT & LEGAL ────────────────────────────
                  _buildSupportLegalCard(),
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }

  // ── Section 1: Invoice Defaults ────────────────────────────────────────────

  Widget _buildProfileLinkCard() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.emerald.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.person_outline_rounded,
            color: AppTheme.emerald,
          ),
        ),
        title: Text('Business profile', style: AppTheme.titleLarge()),
        subtitle: Text(
          'Business identity, currency, tax, logo, and payment details',
          style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textHint,
          size: 14,
        ),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
      ),
    );
  }

  Widget _buildDataBackupCard() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DATA & BACKUP',
            style: AppTheme.labelSmall(color: AppTheme.electricBlue),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage invoices, quotes, and expenses stored on this device.',
            style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          _buildLinkTile(
            icon: Icons.delete_sweep_outlined,
            title: 'Delete invoices, quotes, and expenses',
            onTap: _deleteAllData,
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('Delete local workspace?', style: AppTheme.titleLarge()),
        content: Text(
          'This removes invoices, quotes, expenses, and line items from this device. Your profile and subscription settings stay intact.',
          style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete data',
              style: TextStyle(color: AppTheme.errorRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(databaseServiceProvider).deleteAllData();
    ref.invalidate(invoiceListProvider);
    ref.invalidate(expenseListProvider);
    if (mounted) _showInfo('Local workspace data deleted.');
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildInvoiceDefaultsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.emerald.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppTheme.emerald,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVOICE DEFAULTS',
                      style: AppTheme.labelSmall(color: AppTheme.emerald),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pre-fill options for newly created invoices',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Field 1: Default Language
          Text('DEFAULT LANGUAGE', style: AppTheme.labelSmall()),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButtonFormField<String>(
                initialValue: _languages.contains(_selectedLanguage)
                    ? _selectedLanguage
                    : _languages.first,
                dropdownColor: AppTheme.bgCard,
                isExpanded: true,
                style: AppTheme.bodyMedium(
                  color: AppTheme.textPrimary,
                ).copyWith(fontWeight: FontWeight.w600),
                decoration: const InputDecoration(border: InputBorder.none),
                items: _languages.map((lang) {
                  return DropdownMenuItem(value: lang, child: Text(lang));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    _saveDefaultLanguage(val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Field 2: Default Tax Rate (%)
          Text(
            'DEFAULT TAX RATE FOR NEW INVOICES',
            style: AppTheme.labelSmall(),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _taxRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTheme.bodyMedium(
              color: AppTheme.textPrimary,
            ).copyWith(fontWeight: FontWeight.w500),
            onChanged: _saveDefaultTaxRate,
            decoration: InputDecoration(
              hintText: 'Leave blank for no tax',
              hintStyle: AppTheme.bodyMedium(color: AppTheme.textHint),
              prefixIcon: const Icon(
                Icons.percent_rounded,
                color: AppTheme.emerald,
                size: 18,
              ),
              filled: true,
              fillColor: Colors.white.withAlpha(10),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppTheme.emerald,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Field 3: Default Footer Notes
          Text('DEFAULT FOOTER NOTES', style: AppTheme.labelSmall()),
          const SizedBox(height: 6),
          TextFormField(
            controller: _notesController,
            maxLines: 2,
            style: AppTheme.bodyMedium(
              color: AppTheme.textPrimary,
            ).copyWith(fontWeight: FontWeight.w500),
            onChanged: _saveDefaultNotes,
            decoration: InputDecoration(
              hintText: 'e.g. Thank you for your business!',
              hintStyle: AppTheme.bodyMedium(color: AppTheme.textHint),
              prefixIcon: const Icon(
                Icons.edit_note_rounded,
                color: AppTheme.emerald,
                size: 20,
              ),
              filled: true,
              fillColor: Colors.white.withAlpha(10),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppTheme.emerald,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2: Account & Pro ──────────────────────────────────────────────

  Widget _buildAccountProCard(bool isPro) {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppBrandIcon(size: 42, borderRadius: 12, showGlow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACCOUNT & PRO',
                      style: AppTheme.labelSmall(color: AppTheme.warningAmber),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Security, subscription status & purchase restoration',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ListTile 1: Pro Subscription Status / Upgrade
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Pro Subscription',
              style: AppTheme.bodyLarge().copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              isPro
                  ? 'Unlimited invoices, modern PDF templates & tax analytics'
                  : 'Upgrade to unlock custom branding & PDF templates',
              style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
            ),
            trailing: isPro
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.emerald.withAlpha(100),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.emerald.withAlpha(40),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('👑 ', style: TextStyle(fontSize: 12)),
                        Text(
                          'PRO',
                          style: AppTheme.labelSmall(
                            color: AppTheme.emerald,
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emerald,
                      foregroundColor: AppTheme.bgDeep,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PaywallScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Upgrade',
                      style: AppTheme.labelSmall(
                        color: AppTheme.bgDeep,
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
            // The Upgrade button above owns navigation. Keeping a second
            // ListTile tap handler here can push the paywall twice on a tap.
            onTap: null,
          ),
          const Divider(color: AppTheme.glassBorder, height: 24),

          // ListTile 2: Restore Purchases
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.restore_rounded,
                color: AppTheme.emerald,
                size: 20,
              ),
            ),
            title: Text(
              'Restore Purchases',
              style: AppTheme.bodyLarge().copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Restore active App Store subscriptions',
              style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppTheme.textHint,
              size: 14,
            ),
            onTap: _restorePurchases,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.emerald.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.security_rounded,
                  color: AppTheme.emerald,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SECURITY',
                      style: AppTheme.labelSmall(color: AppTheme.emerald),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Protect your financial information',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.lock_outline_rounded,
              color: AppTheme.emerald,
              size: 24,
            ),
            title: Text(
              'App Lock',
              style: AppTheme.bodyLarge().copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _appLockEnabled
                  ? _appLockMode == AppLockMode.biometrics
                        ? 'Enabled — Face ID / Touch ID required to open the app'
                        : 'Enabled — password or PIN required to open the app'
                  : 'Choose Face ID / Touch ID or a password / PIN',
              style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
            ),
            trailing: Switch.adaptive(
              value: _appLockEnabled,
              activeThumbColor: AppTheme.emerald,
              onChanged: _securityActionInProgress ? null : _toggleAppLock,
            ),
            onTap: _changeAppLockMethod,
          ),
        ],
      ),
    );
  }

  // ── Section 4: Support & Legal ─────────────────────────────────────────────

  Widget _buildSupportLegalCard() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.electricBlue.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: AppTheme.electricBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUPPORT & LEGAL',
                      style: AppTheme.labelSmall(color: AppTheme.electricBlue),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'App assistance and feedback',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Item 1: Share App
          _buildLinkTile(
            icon: Icons.ios_share_rounded,
            title: 'Share App',
            onTap: _shareApp,
          ),
          const Divider(color: AppTheme.glassBorder, height: 16),

          // Item 2: Rate Us
          _buildLinkTile(
            icon: Icons.star_border_rounded,
            title: 'Rate Us',
            onTap: () => _launchURL(_appStoreReviewUrl),
          ),
          const Divider(color: AppTheme.glassBorder, height: 16),

          // Item 3: Contact Support
          _buildLinkTile(
            icon: Icons.email_outlined,
            title: 'Contact Support',
            onTap: () => _launchURL(
              'mailto:zaykarda@yahoo.com?subject=Centsio%20App%20Support',
            ),
          ),
          const Divider(color: AppTheme.glassBorder, height: 16),

          // Item 4: Privacy Policy
          _buildLinkTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () => _launchURL(
              'https://centsioai.blogspot.com/2026/08/centsioaiprivacypremium.html',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.emerald, size: 20),
      title: Text(
        title,
        style: AppTheme.bodyLarge().copyWith(fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        color: AppTheme.textHint,
        size: 14,
      ),
      onTap: onTap,
    );
  }
}
