/// Sales transaction model representing individual sale records
class SalesTransaction {
  final String date;
  final String invoiceNumber;
  final String? userableName;
  final String? userableMobile;
  final double salesWithoutTax;
  final double salesTax;
  final double salesWithTax;
  final String payMethod;
  final String inquery;
  final double creditor;
  final double debtor;
  final double balance;

  SalesTransaction({
    required this.date,
    required this.invoiceNumber,
    this.userableName,
    this.userableMobile,
    required this.salesWithoutTax,
    required this.salesTax,
    required this.salesWithTax,
    required this.payMethod,
    required this.inquery,
    required this.creditor,
    required this.debtor,
    required this.balance,
  });

  factory SalesTransaction.fromJson(Map<String, dynamic> json) {
    return SalesTransaction(
      date: json['date'] ?? '',
      invoiceNumber: json['invoice_number'] ?? '',
      userableName: json['userable_name'],
      userableMobile: json['userable_mobile'],
      salesWithoutTax:
          double.tryParse(json['sales_without_tax']?.toString() ?? '0') ?? 0.0,
      salesTax: double.tryParse(json['sales_tax']?.toString() ?? '0') ?? 0.0,
      salesWithTax:
          double.tryParse(json['sales_with_tax']?.toString() ?? '0') ?? 0.0,
      payMethod: json['pay_method'] ?? '',
      inquery: json['inquery'] ?? '',
      creditor: double.tryParse(json['creditor']?.toString() ?? '0') ?? 0.0,
      debtor: double.tryParse(json['debtor']?.toString() ?? '0') ?? 0.0,
      balance: double.tryParse(json['balance']?.toString() ?? '0') ?? 0.0,
    );
  }
}

/// Pagination links model
class PaginationLinks {
  final String? first;
  final String? last;
  final String? prev;
  final String? next;

  PaginationLinks({
    this.first,
    this.last,
    this.prev,
    this.next,
  });

  factory PaginationLinks.fromJson(Map<String, dynamic> json) {
    return PaginationLinks(
      first: json['first'],
      last: json['last'],
      prev: json['prev'],
      next: json['next'],
    );
  }
}

/// Pagination meta model
class PaginationMeta {
  final int currentPage;
  final int from;
  final int lastPage;
  final String path;
  final int perPage;
  final int to;
  final int total;

  PaginationMeta({
    required this.currentPage,
    required this.from,
    required this.lastPage,
    required this.path,
    required this.perPage,
    required this.to,
    required this.total,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) {
    return PaginationMeta(
      currentPage: json['current_page'] ?? 1,
      from: json['from'] ?? 1,
      lastPage: json['last_page'] ?? 1,
      path: json['path'] ?? '',
      perPage: json['per_page'] ?? 15,
      to: json['to'] ?? 15,
      total: json['total'] ?? 0,
    );
  }
}

/// Sales report response model
class SalesReportResponse {
  final List<SalesTransaction> data;
  final PaginationLinks links;
  final PaginationMeta meta;
  final int status;
  final String? maintenance;
  final String? today;
  final Map<String, dynamic>? dateRange;

  SalesReportResponse({
    required this.data,
    required this.links,
    required this.meta,
    required this.status,
    this.maintenance,
    this.today,
    this.dateRange,
  });

  factory SalesReportResponse.fromJson(Map<String, dynamic> json) {
    return SalesReportResponse(
      data: (json['data'] as List?)
              ?.map((e) => SalesTransaction.fromJson(e))
              .toList() ??
          [],
      links: PaginationLinks.fromJson(json['links'] ?? {}),
      meta: PaginationMeta.fromJson(json['meta'] ?? {}),
      status: json['status'] ?? 200,
      maintenance: json['maintenance'],
      today: json['today'],
      dateRange: json['date_range'],
    );
  }
}

/// Sales summary details model
class SalesSummaryDetails {
  final double sales;
  final double refund;
  final double netSales;
  final double bank;
  final double card;
  final double stc;
  final double cash;
  final double benefit;

  SalesSummaryDetails({
    required this.sales,
    required this.refund,
    required this.netSales,
    required this.bank,
    required this.card,
    required this.stc,
    required this.cash,
    required this.benefit,
  });

  factory SalesSummaryDetails.fromJson(Map<String, dynamic> json) {
    return SalesSummaryDetails(
      sales: double.tryParse(json['sales']?.toString() ?? '0') ?? 0.0,
      refund: double.tryParse(json['refund']?.toString() ?? '0') ?? 0.0,
      netSales: double.tryParse(json['net_sales']?.toString() ?? '0') ?? 0.0,
      bank: double.tryParse(json['bank']?.toString() ?? '0') ?? 0.0,
      card: double.tryParse(json['card']?.toString() ?? '0') ?? 0.0,
      stc: double.tryParse(json['stc']?.toString() ?? '0') ?? 0.0,
      cash: double.tryParse(json['cash']?.toString() ?? '0') ?? 0.0,
      benefit: double.tryParse(json['benefit']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, double> get paymentMethods => {
        'Bank': bank,
        'Card': card,
        'STC': stc,
        'Cash': cash,
        'Benefit': benefit,
      };
}
