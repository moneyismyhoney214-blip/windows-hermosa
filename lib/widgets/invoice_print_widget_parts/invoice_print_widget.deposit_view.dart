// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

/// Deposit-receipt view (فاتورة العربون).
///
/// Triggered by `data!.kind == 'deposit'`. The dashboard prints this layout
/// after the cashier creates a deposit; we mirror it field-for-field so the
/// printed slip from the cash app matches what the customer would receive
/// from the web dashboard.
///
/// Differences from the cashier receipt:
///   * Receipt-number badge labelled `DP-NNN` (deposit number).
///   * Dual title: "فاتورة العربون" + "الفاتورة الضريبية المبسطة".
///   * Single-column services table (no qty / no per-item price — the
///     dashboard intentionally hides them so the customer only sees what
///     they're paying a deposit toward).
///   * Three-row tax breakdown: pre-tax / VAT / post-tax.
///   * Booking-date row alongside the issue date/time so the customer
///     remembers when their appointment is.
extension InvoicePrintWidgetDepositView on InvoicePrintWidget {
  Widget _buildDepositView() {
    final width = _receiptWidth;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 2),
        _buildDepositMetaTable(),
        const SizedBox(height: 3),
        _buildDepositTitle(),
        const SizedBox(height: 2),
        _buildDepositClientTable(),
        const SizedBox(height: 3),
        _buildDepositServicesTable(width),
        const SizedBox(height: 3),
        _buildDepositTotals(),
        const SizedBox(height: 3),
        _buildQrSection(),
        // Only render the refund/exchange policy when the API actually
        // returned text. `_resolvePolicyBody()` returns null when both
        // languages are empty / whitespace, so the whole block — header,
        // border, and trailing spacer — is skipped.
        if (_resolvePolicyBody() != null) ...[
          _buildDepositPolicy(),
          const SizedBox(height: 2),
        ],
        _buildDepositThanks(),
      ],
    );
  }

  Widget _buildDepositMetaTable() {
    final receipt = data!;
    final issueDate = receipt.issueDate ?? '';
    final issueTime = receipt.issueTime ?? '';
    final bookingDate = receipt.bookingDate ?? '';
    final cashier = receipt.cashierName ?? '';
    final taxNo = receipt.vatNumber;
    final crNo = receipt.commercialRegisterNumber ?? '';

    final rows = <_DepositMetaRow>[
      if (cashier.isNotEmpty)
        _DepositMetaRow(
          labelAr: 'الكاشير',
          labelEn: 'Cashier',
          value: cashier,
        ),
      if (taxNo.isNotEmpty)
        _DepositMetaRow(
          labelAr: 'الرقم الضريبي',
          labelEn: 'Tax Number',
          value: taxNo,
        ),
      if (crNo.isNotEmpty)
        _DepositMetaRow(
          labelAr: 'رقم السجل التجاري',
          labelEn: 'Commercial Register Number',
          value: crNo,
        ),
      if (issueDate.isNotEmpty)
        _DepositMetaRow(labelAr: 'التاريخ', labelEn: 'Date', value: issueDate),
      if (issueTime.isNotEmpty)
        _DepositMetaRow(labelAr: 'الوقت', labelEn: 'Time', value: issueTime),
      if (bookingDate.isNotEmpty)
        _DepositMetaRow(
          labelAr: 'تاريخ الحجز',
          labelEn: 'Booking Date',
          value: bookingDate,
        ),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Colors.black, width: 0.5),
                      ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              child: _depositMetaRowWidget(rows[i]),
            ),
        ],
      ),
    );
  }

  /// Inline label row — keeps both languages on the SAME line so the
  /// receipt doesn't double in length when secondary language is enabled.
  /// Falls back to a single-language row when the secondary label is
  /// empty (translations service returned no value).
  Widget _depositMetaRowWidget(_DepositMetaRow row) {
    final primaryLabel = _ml(ar: row.labelAr, en: row.labelEn);
    final secondaryLabel = _sl(ar: row.labelAr, en: row.labelEn);
    final inlineLabel = secondaryLabel.isEmpty
        ? primaryLabel
        : '$primaryLabel / $secondaryLabel';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            inlineLabel,
            style: GoogleFonts.tajawal(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Text(
            row.value,
            textAlign: TextAlign.end,
            style: GoogleFonts.tajawal(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDepositTitle() {
    final mainSecondary = _sl(ar: 'فاتورة العربون', en: 'Deposit Invoice');
    final subSecondary = _sl(
      ar: 'الفاتورة الضريبية المبسطة',
      en: 'Simplified Tax Invoice',
    );
    final mainLabel = mainSecondary.isEmpty
        ? _ml(ar: 'فاتورة العربون', en: 'Deposit Invoice')
        : '${_ml(ar: 'فاتورة العربون', en: 'Deposit Invoice')} / $mainSecondary';
    final subLabel = subSecondary.isEmpty
        ? _ml(
            ar: 'الفاتورة الضريبية المبسطة',
            en: 'Simplified Tax Invoice',
          )
        : '${_ml(ar: 'الفاتورة الضريبية المبسطة', en: 'Simplified Tax Invoice')} / $subSecondary';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.black, width: 1),
          bottom: BorderSide(color: Colors.black, width: 1),
        ),
      ),
      child: Column(
        children: [
          Text(
            mainLabel,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          Text(
            subLabel,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositClientTable() {
    final receipt = data!;
    final name = receipt.clientName ?? '';
    final phone = receipt.clientPhone ?? '';
    if (name.isEmpty && phone.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: Column(
        children: [
          if (name.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: phone.isNotEmpty
                  ? const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.black, width: 0.5),
                      ),
                    )
                  : null,
              child: _depositMetaRowWidget(
                _DepositMetaRow(
                  labelAr: 'اسم العميل',
                  labelEn: 'Client Name',
                  value: name,
                ),
              ),
            ),
          if (phone.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              child: _depositMetaRowWidget(
                _DepositMetaRow(
                  labelAr: 'جوال العميل',
                  labelEn: 'Client Phone',
                  value: phone,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDepositServicesTable(double width) {
    final receipt = data!;
    if (receipt.items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — single inline label "الخدمة / Service"
          Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: const BoxDecoration(
              color: Color(0xFFEFEFEF),
              border: Border(bottom: BorderSide(color: Colors.black, width: 1)),
            ),
            child: Builder(builder: (_) {
              final secondary = _sl(ar: 'الخدمة', en: 'Service');
              final label = secondary.isEmpty
                  ? _ml(ar: 'الخدمة', en: 'Service')
                  : '${_ml(ar: 'الخدمة', en: 'Service')} / $secondary';
              return Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              );
            }),
          ),
          for (var i = 0; i < receipt.items.length; i++)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                border: i == receipt.items.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Colors.black, width: 0.5),
                      ),
              ),
              child: Text(
                receipt.items[i].nameAr.isNotEmpty
                    ? receipt.items[i].nameAr
                    : receipt.items[i].nameEn,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDepositTotals() {
    final receipt = data!;
    final fmt = (double v) => v.toStringAsFixed(ApiConstants.digitsNumber);
    final currencyAr = ApiConstants.currency;

    final rows = <_DepositTotalRow>[
      _DepositTotalRow(
        labelAr: 'الإجمالي قبل الضريبة',
        labelEn: 'Total Before Tax',
        value: fmt(receipt.totalExclVat),
      ),
      _DepositTotalRow(
        labelAr: 'قيمة الضريبة',
        labelEn: 'Tax Amount',
        value: fmt(receipt.vatAmount),
      ),
      _DepositTotalRow(
        labelAr: 'الإجمالي بعد الضريبة',
        labelEn: 'Total After Tax',
        value: fmt(receipt.totalInclVat),
        emphasised: true,
      ),
    ];

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color:
                    rows[i].emphasised ? const Color(0xFFEFEFEF) : Colors.white,
                border: i == rows.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Colors.black, width: 0.5),
                      ),
              ),
              child: Builder(builder: (_) {
                final primaryLabel =
                    _ml(ar: rows[i].labelAr, en: rows[i].labelEn);
                final secondaryLabel =
                    _sl(ar: rows[i].labelAr, en: rows[i].labelEn);
                final inlineLabel = secondaryLabel.isEmpty
                    ? primaryLabel
                    : '$primaryLabel / $secondaryLabel';
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Text(
                        inlineLabel,
                        style: GoogleFonts.tajawal(
                          fontSize: rows[i].emphasised ? 20 : 18,
                          fontWeight: rows[i].emphasised
                              ? FontWeight.w900
                              : FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(
                        '${rows[i].value} $currencyAr',
                        textAlign: TextAlign.end,
                        style: GoogleFonts.tajawal(
                          fontSize: rows[i].emphasised ? 21 : 19,
                          fontWeight: rows[i].emphasised
                              ? FontWeight.w900
                              : FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
        ],
      ),
    );
  }

  /// Pick the policy text that should print, or null if the seller didn't
  /// configure one. Mirrors the language fallback used by [_ml]/[_sl] so
  /// the policy follows the printer's primary language but won't drop the
  /// content entirely if only the secondary language is filled in.
  String? _resolvePolicyBody() {
    final receipt = data;
    if (receipt == null) return null;
    final ar = (receipt.returnPolicyAr ?? '').trim();
    final en = (receipt.returnPolicyEn ?? '').trim();
    final primary = primaryLang == 'ar' ? ar : en;
    final secondary = primaryLang == 'ar' ? en : ar;
    if (primary.isNotEmpty) return primary;
    if (secondary.isNotEmpty) return secondary;
    return null;
  }

  Widget _buildDepositPolicy() {
    final body = _resolvePolicyBody();
    if (body == null) return const SizedBox.shrink();

    final policySecondary =
        _sl(ar: 'سياسة الاسترجاع والاستبدال', en: 'Refund & Exchange Policy');
    final policyTitle = policySecondary.isEmpty
        ? _ml(
            ar: 'سياسة الاسترجاع والاستبدال',
            en: 'Refund & Exchange Policy',
          )
        : '${_ml(ar: 'سياسة الاسترجاع والاستبدال', en: 'Refund & Exchange Policy')} / $policySecondary';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: Column(
        children: [
          Text(
            policyTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositThanks() {
    final thanksSecondary =
        _sl(ar: 'شكرا لثقتكم بنا', en: 'Thank you for trusting us');
    final thanks = thanksSecondary.isEmpty
        ? _ml(ar: 'شكرا لثقتكم بنا', en: 'Thank you for trusting us')
        : '${_ml(ar: 'شكرا لثقتكم بنا', en: 'Thank you for trusting us')} / $thanksSecondary';

    return Column(
      children: [
        Text(
          thanks,
          textAlign: TextAlign.center,
          style: GoogleFonts.tajawal(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
        Text(
          'hermosaapp.com',
          textAlign: TextAlign.center,
          style: GoogleFonts.tajawal(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}

class _DepositMetaRow {
  final String labelAr;
  final String labelEn;
  final String value;
  const _DepositMetaRow({
    required this.labelAr,
    required this.labelEn,
    required this.value,
  });
}

class _DepositTotalRow {
  final String labelAr;
  final String labelEn;
  final String value;
  final bool emphasised;
  const _DepositTotalRow({
    required this.labelAr,
    required this.labelEn,
    required this.value,
    this.emphasised = false,
  });
}
