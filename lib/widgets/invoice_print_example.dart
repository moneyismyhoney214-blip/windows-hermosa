import 'package:flutter/material.dart';
import '../models/receipt_data.dart';
import 'invoice_print_widget.dart';

/// مثال على استخدام InvoicePrintWidget مع البيانات الكاملة
class InvoicePrintExample extends StatelessWidget {
  const InvoicePrintExample({super.key});

  @override
  Widget build(BuildContext context) {
    // بيانات الفاتورة التجريبية
    final sampleData = OrderReceiptData(
      sellerNameAr: 'مركز العناية بالسيارات',
      sellerNameEn: 'Car Care Center',
      sellerLogo: 'https://cdn-icons-png.flaticon.com/512/2962/2962303.png',
      branchName: 'فرع السلامة',
      branchAddress: 'جدة، حي السلامة، شارع الأمير سلطان',
      branchMobile: '0501234567',
      vatNumber: '300123456700003',
      invoiceNumber: 'INV-2023-089',
      issueDateTime: '2023-11-15T09:45:00',
      issueDate: '2023-11-15',
      issueTime: '09:45:00',
      totalExclVat: 310.0,
      vatAmount: 45.0,
      totalInclVat: 345.0,
      paymentMethod: 'نقدي: 100, مدى: 245',
      qrCodeBase64: 'ExampleQRCodeData',
      items: [
        ReceiptItem(
          nameAr: 'غسيل بخار كامل',
          nameEn: 'Full Steam Wash',
          quantity: 1,
          unitPrice: 150.0,
          total: 150.0,
          addons: [
            ReceiptAddon(
              nameAr: 'تلميع داخلي',
              nameEn: 'Interior Polish',
              price: 50.0,
            ),
          ],
        ),
        ReceiptItem(
          nameAr: 'تغيير زيت',
          nameEn: 'Oil Change',
          quantity: 1,
          unitPrice: 80.0,
          total: 80.0,
          addons: [
            ReceiptAddon(
              nameAr: 'فلتر زيت أصلي',
              nameEn: 'Original Oil Filter',
              price: 0.0,
            ),
          ],
        ),
        ReceiptItem(
          nameAr: 'معطر سيارة',
          nameEn: 'Car Air Freshener',
          quantity: 2,
          unitPrice: 15.0,
          total: 30.0,
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('مثال الفاتورة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () {
              // هنا يمكن إضافة كود الطباعة
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('جاري الطباعة...')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // أزرار التبديل بين عرض Widget و HTML
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          appBar: AppBar(title: const Text('عرض Widget')),
                          body: InvoicePrintWidget(
                            data: sampleData,
                            orderType: 'restaurant_parking',
                            tableNumber: 'T-12',
                            carNumber: 'ABC 1234',
                            dailyOrderNumber: '55',
                            carBrand: 'Toyota',
                            carModel: 'Camry',
                            carPlateNumber: 'ح ب ر 1234',
                            carYear: '2022',
                            clientName: 'عبدالله عمر',
                            clientPhone: '0555555555',
                            clientTaxNumber: '312345678900003',
                            commercialRegisterNumber: '1010101010',
                            returnPolicy: 'يرجى الاحتفاظ بالفاتورة للمراجعة.\nضمان الخدمة لمدة 24 ساعة.',
                            useHtmlView: false,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('عرض Widget'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          appBar: AppBar(title: const Text('عرض HTML')),
                          body: InvoicePrintWidget(
                            data: sampleData,
                            orderType: 'restaurant_parking',
                            tableNumber: 'T-12',
                            carNumber: 'ABC 1234',
                            dailyOrderNumber: '55',
                            carBrand: 'Toyota',
                            carModel: 'Camry',
                            carPlateNumber: 'ح ب ر 1234',
                            carYear: '2022',
                            clientName: 'عبدالله عمر',
                            clientPhone: '0555555555',
                            clientTaxNumber: '312345678900003',
                            commercialRegisterNumber: '1010101010',
                            returnPolicy: 'يرجى الاحتفاظ بالفاتورة للمراجعة.\nضمان الخدمة لمدة 24 ساعة.',
                            useHtmlView: true,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('عرض HTML'),
                ),
              ],
            ),
          ),
          // عرض الفاتورة الافتراضي
          Expanded(
            child: InvoicePrintWidget(
              data: sampleData,
              orderType: 'restaurant_parking',
              tableNumber: 'T-12',
              carNumber: 'ABC 1234',
              dailyOrderNumber: '55',
              carBrand: 'Toyota',
              carModel: 'Camry',
              carPlateNumber: 'ح ب ر 1234',
              carYear: '2022',
              clientName: 'عبدالله عمر',
              clientPhone: '0555555555',
              clientTaxNumber: '312345678900003',
              commercialRegisterNumber: '1010101010',
              returnPolicy: 'يرجى الاحتفاظ بالفاتورة للمراجعة.\nضمان الخدمة لمدة 24 ساعة.',
              useHtmlView: false,
            ),
          ),
        ],
      ),
    );
  }
}
