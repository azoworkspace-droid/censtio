import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';

import '../providers/entitlement_provider.dart';
import '../providers/currency_provider.dart';
import '../services/gemini_service.dart';
import '../services/analytics_service.dart';
import '../services/revenuecat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'add_expense_screen.dart';
import 'all_invoices_screen.dart';
import 'app_settings_screen.dart';
import 'create_invoice_screen.dart';
import '../widgets/voice_assistant_dialog.dart';
import '../widgets/pro_offer_sheet.dart';
import 'dashboard_screen.dart';
import 'expenses_screen.dart';
import 'paywall_screen.dart';

class MainNavScreen extends ConsumerStatefulWidget {
  const MainNavScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends ConsumerState<MainNavScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showProOfferIfNeeded();
    });
  }

  Future<void> _showProOfferIfNeeded() async {
    // Let the Home tab render first so the offer feels like an in-context
    // welcome offer rather than replacing the launch destination.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    if (await RevenueCatService.isProUser() || !mounted) return;

    // A free user should always see the upgrade surface. If RevenueCat is
    // unavailable, the dialog remains visible and explains that checkout will
    // be enabled once the real StoreKit products are connected.
    final offering = RevenueCatService.isConfigured
        ? await RevenueCatService.getCurrentOffering().timeout(
            const Duration(seconds: 4),
            onTimeout: () => null,
          )
        : null;
    if (!mounted) return;

    await showDialog<bool>(
      context: context,
      useSafeArea: true,
      barrierDismissible: true,
      barrierColor: Colors.black.withAlpha(185),
      builder: (_) => ProOfferSheet(offering: offering),
    );
  }

  final List<Widget> _screens = const [
    DashboardScreen(),
    AllInvoicesScreen(),
    ExpensesScreen(),
    AppSettingsScreen(),
  ];

  Future<void> _showMagicCreateMenu(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        // Keep the parent screen context for work that continues after this
        // bottom sheet is dismissed. AI camera/network operations are async;
        // the sheet's own State is disposed as soon as it is popped.
        return _CreateMenuBottomSheet(hostContext: context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildFloatingGlassNavBar(context),
    );
  }

  Widget _buildFloatingGlassNavBar(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        height: 72,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Light Frosted Glass Background Shell
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 66,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard.withAlpha(230), // Dark Frosted Glass
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppTheme.glassBorder, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 24,
                        spreadRadius: 2,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: AppTheme.emeraldGlow,
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildNavItem(
                              0,
                              Icons.home_outlined,
                              Icons.home_rounded,
                              'Home',
                            ),
                            _buildNavItem(
                              1,
                              Icons.receipt_long_outlined,
                              Icons.receipt_long_rounded,
                              'Invoices',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 56), // Space for center FAB
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildNavItem(
                              2,
                              Icons.account_balance_wallet_outlined,
                              Icons.account_balance_wallet_rounded,
                              'Expenses',
                            ),
                            _buildNavItem(
                              3,
                              Icons.settings_outlined,
                              Icons.settings_rounded,
                              'Settings',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Floating Center (+) Button
            Positioned(
              top: -10,
              child: GestureDetector(
                onTap: () => _showMagicCreateMenu(context),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00F5A0), Color(0xFF00D990)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white, width: 3.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00F5A0).withValues(alpha: 0.5),
                        blurRadius: 16,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Color(0xFF0F172A),
                    size: 32,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final isSelected = _currentIndex == index;
    final activeColor = AppTheme.emerald;
    final inactiveColor = AppTheme.textHint;

    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateMenuBottomSheet extends ConsumerStatefulWidget {
  const _CreateMenuBottomSheet({required this.hostContext});

  /// Context belonging to MainNavScreen, which remains mounted after this
  /// bottom sheet closes. It is intentionally used for dialogs, snackbars,
  /// and navigation after camera/Gemini awaits.
  final BuildContext hostContext;

  @override
  ConsumerState<_CreateMenuBottomSheet> createState() =>
      _CreateMenuBottomSheetState();
}

class _CreateMenuBottomSheetState
    extends ConsumerState<_CreateMenuBottomSheet> {
  int _selectedTab = 0; // 0: Invoices, 1: Quotes, 2: Expenses

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(entitlementProvider).value ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXL),
        ),
        border: Border(
          top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag indicator handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: AppTheme.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text('Create New...', style: AppTheme.headlineMedium()),
          const SizedBox(height: 16),

          // Segmented Control
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              children: [
                _buildTab(0, 'Invoices'),
                _buildTab(1, 'Quotes'),
                _buildTab(2, 'Expenses'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Animated Content Based on Selected Tab
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            layoutBuilder: (currentChild, previousChildren) =>
                currentChild ?? const SizedBox.shrink(),
            child: _buildTabContent(isPro),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.emerald.withAlpha(40)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            border: Border.all(
              color: isSelected
                  ? AppTheme.emerald.withAlpha(80)
                  : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style:
                AppTheme.labelSmall(
                  color: isSelected ? AppTheme.emerald : AppTheme.textHint,
                ).copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(bool isPro) {
    switch (_selectedTab) {
      case 0:
        return _buildInvoicesContent(isPro);
      case 1:
        return _buildQuotesContent(isPro);
      case 2:
        return _buildExpensesContent(isPro);
      default:
        return const SizedBox();
    }
  }

  Widget _buildInvoicesContent(bool isPro) {
    return Column(
      key: const ValueKey('invoices'),
      children: [
        _MagicOptionCard(
          icon: Icons.description_outlined,
          iconColor: AppTheme.emerald,
          title: 'Manual Invoice',
          subtitle: 'Create a custom invoice from scratch',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              widget.hostContext,
              MaterialPageRoute(builder: (_) => const CreateInvoiceScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _MagicOptionCard(
          icon: Icons.document_scanner_outlined,
          iconColor: AppTheme.electricBlue,
          title: 'Scan to Invoice',
          subtitle:
              'PRO — Unlimited AI scans · turn a document into an invoice',
          isPro: true,
          onTap: () => _handleAIScanInvoice(isPro, isQuote: false),
        ),
        const SizedBox(height: 12),
        _MagicOptionCard(
          icon: Icons.mic_none_rounded,
          iconColor: AppTheme.emerald,
          title: 'Create Invoice by Voice',
          subtitle: 'PRO — AI voice input · describe the invoice naturally',
          isPro: true,
          onTap: () => _handleAIVoice(isPro, isQuote: false),
        ),
      ],
    );
  }

  Widget _buildQuotesContent(bool isPro) {
    return Column(
      key: const ValueKey('quotes'),
      children: [
        _MagicOptionCard(
          icon: Icons.request_quote_outlined,
          iconColor: AppTheme.warningAmber,
          title: 'Manual Quote',
          subtitle: 'Create a quote or estimate from scratch',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              widget.hostContext,
              MaterialPageRoute(
                builder: (_) => const CreateInvoiceScreen(isQuote: true),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _MagicOptionCard(
          icon: Icons.document_scanner_outlined,
          iconColor: AppTheme.electricBlue,
          title: 'Scan to Quote',
          subtitle: 'PRO — Unlimited AI scans · turn a document into a quote',
          isPro: true,
          onTap: () => _handleAIScanInvoice(isPro, isQuote: true),
        ),
        const SizedBox(height: 12),
        _MagicOptionCard(
          icon: Icons.mic_none_rounded,
          iconColor: AppTheme.emerald,
          title: 'Create Quote by Voice',
          subtitle: 'PRO — AI voice input · describe the quote naturally',
          isPro: true,
          onTap: () => _handleAIVoice(isPro, isQuote: true),
        ),
      ],
    );
  }

  Widget _buildExpensesContent(bool isPro) {
    return Column(
      key: const ValueKey('expenses'),
      children: [
        _MagicOptionCard(
          icon: Icons.receipt_long_outlined,
          iconColor: AppTheme.warningAmber,
          title: 'Add Expense',
          subtitle: 'Record an operational business expense manually',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              widget.hostContext,
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _MagicOptionCard(
          icon: Icons.document_scanner_outlined,
          iconColor: AppTheme.electricBlue,
          title: 'Scan Receipt',
          subtitle: 'PRO — Unlimited AI scans · turn a receipt into an expense',
          isPro: true,
          onTap: () => _handleAIScanReceipt(isPro),
        ),
        const SizedBox(height: 12),
        _MagicOptionCard(
          icon: Icons.mic_none_rounded,
          iconColor: AppTheme.emerald,
          title: 'Create Expense by Voice',
          subtitle: 'PRO — AI voice input · describe the expense naturally',
          isPro: true,
          onTap: () => _handleAIVoiceExpense(isPro),
        ),
      ],
    );
  }

  Future<void> _handleAIScanInvoice(bool isPro, {required bool isQuote}) async {
    unawaited(AnalyticsService.track('invoice_scan_started'));
    // Capture provider values before dismissing this bottom sheet. Its
    // ConsumerState/ref is disposed immediately after Navigator.pop(context).
    final currencySymbol = ref.read(currencySymbolProvider);
    Navigator.pop(context);
    final proStatus = isPro || await RevenueCatService.isProUser();
    if (!widget.hostContext.mounted) return;

    if (!proStatus) {
      Navigator.of(
        widget.hostContext,
      ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }

    final picker = ImagePicker();
    XFile? image;
    try {
      image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1800,
        maxHeight: 2400,
        imageQuality: 85,
        requestFullMetadata: false,
      );
    } catch (_) {
      if (widget.hostContext.mounted) {
        _showErrorSnackBar('Camera permission was denied or unavailable.');
      }
      return;
    }
    if (image == null) return;
    final selectedImage = image;

    if (!widget.hostContext.mounted) return;
    _showAILoadingDialog('✨ Drafting invoice from document...');

    AiInvoiceData? data;
    try {
      final bytes = await selectedImage.readAsBytes();
      if (bytes.isEmpty) {
        throw const AiServiceException(
          'The camera returned an empty photo. Please take the photo again.',
        );
      }
      data = await GeminiService.analyzeDraftForInvoice(
        bytes,
        mimeType: _imageMimeType(selectedImage.path, bytes),
        currencySymbol: currencySymbol,
      );
    } on AiServiceException catch (error) {
      if (widget.hostContext.mounted) {
        Navigator.of(widget.hostContext).pop();
        _showErrorSnackBar(error.message);
      }
      return;
    } catch (error, stackTrace) {
      debugPrint('AI invoice scan failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (widget.hostContext.mounted) {
        Navigator.of(widget.hostContext).pop();
        _showErrorSnackBar(
          'Could not read or analyze the photo. Please take a clearer photo and try again.',
        );
      }
      return;
    }

    if (!widget.hostContext.mounted) return;
    Navigator.of(widget.hostContext).pop(); // pop loading dialog

    if (data == null) {
      _showErrorSnackBar('Failed to extract data from invoice image.');
      return;
    }
    unawaited(AnalyticsService.track('invoice_scan_completed'));
    final invoiceData = data;

    Navigator.of(widget.hostContext).push(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(
          isQuote: isQuote,
          initialClientName: invoiceData.clientName,
          initialItems: invoiceData.items.map((item) => item.toMap()).toList(),
          initialNotes: invoiceData.notes,
        ),
      ),
    );
  }

  Future<void> _handleAIVoice(bool isPro, {required bool isQuote}) async {
    unawaited(AnalyticsService.track('voice_invoice_started'));
    Navigator.pop(context);
    final proStatus = isPro || await RevenueCatService.isProUser();
    if (!widget.hostContext.mounted) return;

    if (!proStatus) {
      Navigator.of(
        widget.hostContext,
      ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }

    final data = await showDialog<Object?>(
      context: widget.hostContext,
      barrierDismissible: false,
      builder: (ctx) => VoiceAssistantDialog(
        title: isQuote ? '🪄 AI Voice Quote' : '🪄 AI Voice Invoice',
      ),
    );

    if (!widget.hostContext.mounted) return;
    if (data is AiInvoiceData) {
      Navigator.of(widget.hostContext).push(
        MaterialPageRoute(
          builder: (_) => CreateInvoiceScreen(
            isQuote: isQuote,
            initialClientName: data.clientName,
            initialItems: data.items.map((item) => item.toMap()).toList(),
            initialNotes: data.notes,
          ),
        ),
      );
    }
  }

  Future<void> _handleAIVoiceExpense(bool isPro) async {
    unawaited(AnalyticsService.track('voice_expense_started'));
    Navigator.pop(context);
    final proStatus = isPro || await RevenueCatService.isProUser();
    if (!widget.hostContext.mounted) return;

    if (!proStatus) {
      Navigator.of(
        widget.hostContext,
      ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }

    final data = await showDialog<Object?>(
      context: widget.hostContext,
      barrierDismissible: false,
      builder: (ctx) => const VoiceAssistantDialog(
        title: '🪄 AI Voice Expense',
        isExpense: true,
      ),
    );

    if (!widget.hostContext.mounted) return;
    if (data is AiExpenseData) {
      // AI only pre-fills the form. The user must review and confirm before
      // the expense is written to the database.
      Navigator.of(widget.hostContext).push(
        MaterialPageRoute(
          builder: (_) => AddExpenseScreen(
            initialAmount: data.amount,
            initialCategory: data.category,
            initialNote: data.note,
          ),
        ),
      );
    } else if (data != null && widget.hostContext.mounted) {
      _showErrorSnackBar('The AI result was incomplete. Please try again.');
    }
  }

  Future<void> _handleAIScanReceipt(bool isPro) async {
    unawaited(AnalyticsService.track('receipt_scan_started'));
    // Capture provider values before dismissing this bottom sheet. Its
    // ConsumerState/ref is disposed immediately after Navigator.pop(context).
    final currencySymbol = ref.read(currencySymbolProvider);
    Navigator.pop(context);
    final proStatus = isPro || await RevenueCatService.isProUser();
    if (!widget.hostContext.mounted) return;

    if (!proStatus) {
      Navigator.of(
        widget.hostContext,
      ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }

    final picker = ImagePicker();
    XFile? image;
    try {
      image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1800,
        maxHeight: 2400,
        imageQuality: 85,
        requestFullMetadata: false,
      );
    } catch (_) {
      if (widget.hostContext.mounted) {
        _showErrorSnackBar('Camera permission was denied or unavailable.');
      }
      return;
    }
    if (image == null) return;
    final selectedImage = image;

    if (!widget.hostContext.mounted) return;
    _showAILoadingDialog('✨ Analyzing receipt...');

    AiExpenseData? data;
    try {
      final bytes = await selectedImage.readAsBytes();
      if (bytes.isEmpty) {
        throw const AiServiceException(
          'The camera returned an empty photo. Please take the photo again.',
        );
      }
      data = await GeminiService.analyzeReceiptForExpense(
        bytes,
        mimeType: _imageMimeType(selectedImage.path, bytes),
        currencySymbol: currencySymbol,
      );
    } on AiServiceException catch (error) {
      if (widget.hostContext.mounted) {
        Navigator.of(widget.hostContext).pop();
        _showErrorSnackBar(error.message);
      }
      return;
    } catch (error, stackTrace) {
      debugPrint('AI receipt scan failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (widget.hostContext.mounted) {
        Navigator.of(widget.hostContext).pop();
        _showErrorSnackBar(
          'Could not read or analyze the photo. Please take a clearer photo and try again.',
        );
      }
      return;
    }

    if (!widget.hostContext.mounted) return;
    Navigator.of(widget.hostContext).pop(); // pop loading dialog

    if (data == null) {
      _showErrorSnackBar('Failed to extract data from receipt.');
      return;
    }
    unawaited(AnalyticsService.track('receipt_scan_completed'));
    final expenseData = data;

    // AI only pre-fills the form. The user must review and confirm before the
    // expense is written to the database.
    Navigator.of(widget.hostContext).push(
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          initialAmount: expenseData.amount,
          initialCategory: expenseData.category,
          initialNote: expenseData.note,
          initialImagePath: selectedImage.path,
        ),
      ),
    );
  }

  void _showAILoadingDialog(String text) {
    showDialog(
      context: widget.hostContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          side: const BorderSide(color: AppTheme.glassBorder, width: 1),
        ),
        content: Row(
          children: [
            const CircularProgressIndicator(color: AppTheme.electricBlue),
            const SizedBox(width: 20),
            Expanded(child: Text(text, style: AppTheme.bodyMedium())),
          ],
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(widget.hostContext).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorRed),
    );
  }

  String _imageMimeType(String path, [Uint8List? bytes]) {
    if (bytes != null && bytes.length >= 12) {
      // Detect the actual encoded format first. iOS can return a temporary
      // filename whose extension does not match the camera output.
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return 'image/jpeg';
      }
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      if (String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
        return 'image/webp';
      }
      // HEIF/HEIC stores an `ftyp` box at byte 4. Both brands are accepted
      // by Gemini, but using the exact MIME type is safer.
      if (String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
        final brand = String.fromCharCodes(bytes.sublist(8, 12));
        if (brand == 'heic' || brand == 'heix') return 'image/heic';
        if (brand == 'heif' || brand == 'mif1') return 'image/heif';
      }
    }

    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }
}

class _MagicOptionCard extends StatelessWidget {
  const _MagicOptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPro = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyLarge().copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isPro) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppTheme.emeraldGradient,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.emerald.withAlpha(80),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('👑 ', style: TextStyle(fontSize: 10)),
                              Text(
                                'PRO',
                                style: AppTheme.labelSmall(
                                  color: AppTheme.bgDeep,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textHint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
