import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invoice.dart';
import '../providers/currency_provider.dart';
import '../services/app_database.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// A single row in the recent-invoices list.
///
/// Shows invoice number, client name, date,
/// amount with dynamic currency symbol, and a coloured status badge.
class InvoiceTile extends ConsumerWidget {
  const InvoiceTile({super.key, required this.invoice, this.onTap});

  final Invoice invoice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencySymbolProvider);
    final currencyCode = ref.watch(currencyCodeProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(color: AppTheme.glassBorder, width: 1),
        ),
        child: Row(
          children: [
            // ── Status dot ─────────────────────────────────────────────────
            _StatusDot(status: invoice.status),
            const SizedBox(width: 14),

            // ── Invoice details ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.invoiceNumber,
                    style: AppTheme.bodyLarge(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(_formatDate(invoice.date), style: AppTheme.bodyMedium()),
                ],
              ),
            ),

            // ── Amount + status badge ───────────────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatCurrency(
                        invoice.totalAmount,
                        currency,
                        currencyCode: currencyCode,
                      ),
                      style: AppTheme.bodyLarge(
                        color: _amountColor(invoice.status),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (invoice.documentType == 'quote') ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.electricBlue.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.electricBlue.withAlpha(80),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'QUOTE',
                            style: AppTheme.labelSmall(
                              color: AppTheme.electricBlue,
                            ),
                          ),
                        ),
                      ],
                      _StatusBadge(status: invoice.status),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static Color _amountColor(InvoiceStatus status) => switch (status) {
    InvoiceStatus.paid => AppTheme.emerald,
    InvoiceStatus.pending => AppTheme.warningAmber,
    InvoiceStatus.overdue => AppTheme.errorRed,
    InvoiceStatus.draft ||
    InvoiceStatus.cancelled ||
    InvoiceStatus.none => AppTheme.textSecondary,
  };
}

// ── Internal widgets ──────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      InvoiceStatus.paid => AppTheme.emerald,
      InvoiceStatus.pending => AppTheme.warningAmber,
      InvoiceStatus.overdue => AppTheme.errorRed,
      InvoiceStatus.draft ||
      InvoiceStatus.cancelled ||
      InvoiceStatus.none => AppTheme.textSecondary,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withAlpha(120), blurRadius: 6)],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
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
        AppTheme.errorRed.withAlpha(180),
        AppTheme.errorRed.withAlpha(20),
      ),
      InvoiceStatus.none => (
        'UNSPECIFIED',
        AppTheme.textSecondary,
        AppTheme.glassBorder,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: AppTheme.labelSmall(color: fg)),
    );
  }
}
