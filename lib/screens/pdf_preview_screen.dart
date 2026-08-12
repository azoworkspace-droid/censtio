import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';

import '../models/invoice.dart';
import '../screens/paywall_screen.dart';
import '../services/app_database.dart';
import '../services/pdf_service.dart';
import '../services/revenuecat_service.dart';
import '../theme/app_theme.dart';

/// Interactive PDF Preview screen with Live Template Switcher and Export Gating.
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({
    super.key,
    required this.invoice,
    required this.client,
    required this.items,
  });

  final Invoice invoice;
  final Client client;
  final List<InvoiceItem> items;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  late String _selectedTemplate;
  PdfPageFormat _pageFormat = PdfPageFormat.a4;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    // Default to 'Classic' or current invoice saved template
    _selectedTemplate = widget.invoice.template ?? 'Classic';
    if (_selectedTemplate == 'Basic') {
      _selectedTemplate = 'Classic';
    }
  }

  Future<void> _handleExport() async {
    // Paywall check for Pro templates ('Modern' or 'Elite')
    if (_selectedTemplate == 'Modern' || _selectedTemplate == 'Elite') {
      final isPro = await RevenueCatService.isProUser();
      if (!isPro) {
        if (mounted) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
        }
        return;
      }
    }

    setState(() => _isExporting = true);

    try {
      final pdfBytes = await PdfService.generateInvoicePdf(
        invoice: widget.invoice,
        client: widget.client,
        items: widget.items,
        templateType: _selectedTemplate,
        pageFormat: _pageFormat,
      );

      await Printing.sharePdf(
        bytes: Uint8List.fromList(pdfBytes),
        filename: '${widget.invoice.invoiceNumber}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting PDF: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: Column(
          children: [
            // PDF Preview Viewport
            Expanded(
              child: PdfPreview(
                build: (format) async => Uint8List.fromList(
                  await PdfService.generateInvoicePdf(
                    invoice: widget.invoice,
                    client: widget.client,
                    items: widget.items,
                    templateType: _selectedTemplate,
                    pageFormat: format,
                  ),
                ),
                pdfFileName: '${widget.invoice.invoiceNumber}.pdf',
                allowSharing: false,
                allowPrinting: false,
                canChangeOrientation: false,
                canChangePageFormat: true,
                canDebug: false,
                initialPageFormat: PdfPageFormat.a4,
                onPageFormatChanged: (format) {
                  if (mounted) setState(() => _pageFormat = format);
                },
                actions: const [],
                loadingWidget: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          color: AppTheme.emerald,
                          strokeWidth: 2.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Rendering PDF Template…',
                        style: AppTheme.bodyMedium(),
                      ),
                    ],
                  ),
                ),
                onError: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Failed to render PDF: $error',
                      style: AppTheme.bodyMedium(color: AppTheme.errorRed),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Template Selector & Export Controls
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusLG),
                ),
                border: Border(
                  top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTemplatePickerRow(),
                  const SizedBox(height: 16),
                  _buildExportButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.bgCard,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.invoice.invoiceNumber, style: AppTheme.titleLarge()),
          Text(widget.client.name, style: AppTheme.bodyMedium()),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: _StatusChip(status: widget.invoice.status),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.glassBorder),
      ),
    );
  }

  Widget _buildTemplatePickerRow() {
    final templates = [
      {'name': 'Classic', 'isPro': false, 'label': 'Classic'},
      {'name': 'Modern', 'isPro': true, 'label': 'Modern'},
      {'name': 'Elite', 'isPro': true, 'label': 'Elite'},
    ];

    return Row(
      children: templates.map((t) {
        final name = t['name'] as String;
        final isPro = t['isPro'] as bool;
        final label = t['label'] as String;
        final isSelected =
            _selectedTemplate == name ||
            (_selectedTemplate == 'Basic' && name == 'Classic');

        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedTemplate = name;
              });
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.emerald.withAlpha(25)
                    : AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(
                  color: isSelected ? AppTheme.emerald : AppTheme.glassBorder,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: AppTheme.bodyLarge(
                            color: isSelected
                                ? AppTheme.emerald
                                : AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPro) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 13,
                          color: AppTheme.warningAmber,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPro ? (name == 'Modern' ? 'Premium' : 'PRO') : 'Free',
                    style: AppTheme.labelSmall(
                      color: isPro
                          ? AppTheme.warningAmber
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExportButton() {
    final isProTemplate =
        _selectedTemplate == 'Modern' || _selectedTemplate == 'Elite';

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.emerald,
          foregroundColor: AppTheme.bgDeep,
          elevation: 6,
          shadowColor: AppTheme.emeraldGlow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          ),
        ),
        onPressed: _isExporting ? null : _handleExport,
        child: _isExporting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: AppTheme.bgDeep,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isProTemplate
                        ? Icons.workspace_premium_rounded
                        : Icons.share_rounded,
                    size: 20,
                    color: AppTheme.bgDeep,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Export & Share Invoice',
                    style: AppTheme.bodyLarge(color: AppTheme.bgDeep),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      InvoiceStatus.paid => (
        'PAID',
        AppTheme.emerald,
        AppTheme.emerald.withAlpha(30),
      ),
      InvoiceStatus.pending => (
        'PENDING',
        AppTheme.warningAmber,
        AppTheme.warningAmber.withAlpha(30),
      ),
      InvoiceStatus.overdue => (
        'OVERDUE',
        AppTheme.errorRed,
        AppTheme.errorRed.withAlpha(30),
      ),
      InvoiceStatus.draft => (
        'DRAFT',
        AppTheme.textSecondary,
        AppTheme.glassBorder,
      ),
      InvoiceStatus.cancelled => (
        'CANCELLED',
        AppTheme.errorRed,
        AppTheme.errorRed.withAlpha(20),
      ),
      InvoiceStatus.none => (
        'UNSPECIFIED',
        AppTheme.textSecondary,
        AppTheme.glassBorder,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withAlpha(80)),
      ),
      child: Text(label, style: AppTheme.labelSmall(color: fg)),
    );
  }
}
