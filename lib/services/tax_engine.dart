import '../models/invoice.dart';
import '../services/app_database.dart';

/// Breakdown returned by [TaxEngine.calculateEstimatedAvailable].
class TaxBreakdown {
  const TaxBreakdown({
    required this.totalRevenue,
    required this.taxReserved,
    required this.expenses,
    required this.safeToSpend,
  });

  /// Sum of [Invoice.totalAmount] for all paid invoices.
  final double totalRevenue;

  /// Amount set aside for taxes using the user's configured default rate.
  final double taxReserved;

  /// Actual total tracked expenses.
  final double expenses;

  /// What the freelancer can safely spend:
  /// `totalRevenue - taxReserved - expenses`.
  final double safeToSpend;

  // ── Convenience ────────────────────────────────────────────────────────────

  /// Returns this breakdown as a plain [Map], useful for display/serialisation.
  Map<String, double> toMap() => {
    'totalRevenue': totalRevenue,
    'taxReserved': taxReserved,
    'expenses': expenses,
    'safeToSpend': safeToSpend,
  };

  @override
  String toString() =>
      'TaxBreakdown(revenue: $totalRevenue, tax: $taxReserved, '
      'expenses: $expenses, safeToSpend: $safeToSpend)';
}

/// Pure business-logic class that computes tax & spending estimates.
///
/// This class is intentionally stateless so it can be used as a singleton
/// Riverpod provider without any lifecycle concerns.
class TaxEngine {
  const TaxEngine();

  /// Calculates an estimate of available funds from paid invoices, the user's
  /// configured default tax rate, and tracked expenses.
  ///
  /// Only invoices with a [InvoiceStatus.paid] status are included in the
  /// revenue calculation. Pending or overdue invoices are ignored because the
  /// cash has not yet been received.
  ///
  /// Returns a [TaxBreakdown] containing all intermediate values as well as
  /// the final [TaxBreakdown.safeToSpend] figure.
  TaxBreakdown calculateEstimatedAvailable(
    List<Invoice> invoices,
    double totalExpenses, {
    double taxRatePercent = 0.0,
  }) {
    // Only count revenue that has actually been received.
    final paidInvoices = invoices.where(
      (inv) => inv.status == InvoiceStatus.paid,
    );

    final totalRevenue = paidInvoices.fold<double>(
      0.0,
      (sum, inv) => sum + inv.totalAmount,
    );

    final normalizedRate = taxRatePercent.clamp(0.0, 100.0).toDouble();
    final taxReserved = totalRevenue * (normalizedRate / 100.0);
    final safeToSpend = totalRevenue - taxReserved - totalExpenses;

    return TaxBreakdown(
      totalRevenue: totalRevenue,
      taxReserved: taxReserved,
      expenses: totalExpenses,
      safeToSpend: safeToSpend,
    );
  }

  /// Backwards-compatible name for callers outside the dashboard.
  TaxBreakdown calculateSafeToSpend(
    List<Invoice> invoices,
    double totalExpenses, {
    double taxRatePercent = 0.0,
  }) => calculateEstimatedAvailable(
    invoices,
    totalExpenses,
    taxRatePercent: taxRatePercent,
  );
}
