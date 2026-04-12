<template>
  <LabelButton id="print-invoice" type="print" @click="printInvoice" />

  <div ref="printArea" class="hidden" :id="id">
    <div class="bill bill-container size-5cm">
      <header>
        <div class="seller-info">
          <div class="logo-container flex justify-center mb-4">
            <img
              :src="model.branch.logo || model.branch.seller.logo"
              alt=""
              class="w-24 h-24 object-contain"
            />
            <!-- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/24/LEGO_logo.svg/2048px-LEGO_logo.svg.png"  class="w-24 h-24 object-contain" alt=""> -->
          </div>
          <div class="info">
            <p class="title font-bold">
              {{ model.branch.seller_name }}
            </p>
            <p>{{ model.branch.address }}</p>
            <p v-if="model.branch.mobile" class="mobile">
              {{ model.branch.mobile }}
            </p>
            <p v-if="model.branch.telephone" class="mobile">
              {{ model.branch.telephone }}
            </p>
          </div>
          <div class="info-bottom">
            <div class="flex justify-center my-2">
              <div
                v-if="model.type && model.order_number"
                class="border-2 border-black px-4 py-1 text-lg font-bold"
              >
                Order# {{ model.order_number }}
              </div>
            </div>
            <div class="flex justify-center my-2">
              <div class="border-2 border-black px-4 py-1 text-lg font-bold">
                {{ model.invoice.invoice_number.replace("#", "") }}
              </div>
            </div>
            <div v-if="model.invoice?.cashier" class="info-bottom-item">
              <p>الكاشير</p>
              <p>{{ model.invoice?.cashier?.fullname }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">कैशियर</p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                کیشیئر
              </p>
              <p v-else>Cashier</p>
            </div>
            <div class="info-bottom-item">
              <p>الرقم الضريبي</p>
              <p>{{ model.branch.seller.tax_number }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                कर संख्या
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ٹیکس نمبر
              </p>
              <p v-else>Tax Number</p>
            </div>
            <div v-if="model.branch.commercial_number" class="info-bottom-item">
              <p>رقم السجل التجاري</p>
              <p>{{ model.branch.commercial_number }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                व्यावसायिक रजिस्टर संख्या
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                تجارتی رجسٹر نمبر
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Ticari Sicil Numarası
              </p>
              <p v-else>Commercial Register Number</p>
            </div>
            <div class="info-bottom-item">
              <p>التاريخ</p>
              <p>{{ model.invoice.date }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">दिनांक</p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                تاریخ
              </p>
              <p v-else>Date</p>
            </div>
            <div class="info-bottom-item">
              <p>الوقت</p>
              <p class="force-ltr">{{ model.invoice.time }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">समय</p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">وقت</p>
              <p v-else>Time</p>
            </div>

            <div
              class="info-bottom-item"
              v-if="model.type && model.type.includes('restaurant')"
            >
              <p>رقم الطلب</p>
              <p class="force-ltr">
                {{ model.booking.daily_order_number }}
              </p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                ऑर्डर संख्या
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                آرڈر نمبر
              </p>
              <p v-else>Order Number</p>
            </div>
            <div v-if="model.invoice?.parent_invoice" class="info-bottom-item">
              <p>الفاتورة الأب</p>
              <p class="force-ltr">
                {{ model.invoice.parent_invoice.invoice_number }}
              </p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                पेरेंट इनवॉइस
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                پیرنٹ انوائس
              </p>
              <p v-else>Parent Invoice</p>
            </div>
            <div class="info-bottom-item" v-if="model.type">
              <p>نوع الطلب</p>
              <p>
                {{
                  $t(
                    "base." +
                      (model.type == "services" ? "restaurant_services" : model.type)
                  )
                }}
              </p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                ऑर्डर प्रकार
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                آرڈر کی قسم
              </p>
              <p v-else>order type</p>
            </div>
            <div class="info-bottom-item" v-if="model.type == 'restaurant_internal'">
              <p>رقم الطاوله</p>
              <p>{{ model.booking?.type_extra?.table_name }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                टेबल संख्या
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ٹیبل نمبر
              </p>
              <p v-else>Table number</p>
            </div>
            <div class="info-bottom-item" v-if="model.type == 'restaurant_parking'">
              <p>رقم السياره</p>
              <p>{{ model.booking?.type_extra?.car_number }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                कार संख्या
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                کار نمبر
              </p>
              <p v-else>car number</p>
            </div>
            <div v-if="model.invoice.original_invoice_number" class="info-bottom-item">
              <p>رقم فاتورة الاسترجاع</p>
              <p class="force-ltr">
                {{ model.invoice.original_invoice_number }}
              </p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                रिफंड इनवॉइस आईडी
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ریفنڈ انوائس آئی ڈی
              </p>
              <p v-else>Refund Invoice ID</p>
            </div>
            <div v-if="model.invoice?.booking_date" class="info-bottom-item">
              <p>تاريخ الحجز</p>
              <p>{{ model.invoice.booking_date }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                बुकिंग दिनांक
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                بکنگ تاریخ
              </p>
              <p v-else>Booking Date</p>
            </div>
          </div>
        </div>
      </header>
      <section>
        <div v-if="model.invoice_title" class="invoice-title">
          <p>{{ model.invoice_title.text }}</p>
          <p>{{ model.invoice_title.textAlt }}</p>
        </div>
        <div v-else class="invoice-title">
          <p>{{ title.text }}</p>
          <p>{{ title.textAlt }}</p>
        </div>
        <div v-if="model.invoice?.client">
          <div class="client-info">
            <div class="client-info-item">
              <p class="font-bold">اسم العميل</p>
              <p
                class="font-bold"
                v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
              >
                ग्राहक का नाम
              </p>
              <p
                class="font-bold"
                v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
              >
                کلائنٹ کا نام
              </p>
              <p
                class="font-bold"
                v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
              >
                Müşteri Adı
              </p>
              <p class="font-bold" v-else>Client Name</p>
              <p>{{ model.invoice.client.name }}</p>
            </div>
            <div class="client-info-item">
              <p class="font-bold">جوال العميل</p>
              <p
                class="font-bold"
                v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
              >
                ग्राहक फोन
              </p>
              <p
                class="font-bold"
                v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
              >
                کلائنٹ فون
              </p>
              <p
                class="font-bold"
                v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
              >
                Müşteri Telefonu
              </p>
              <p class="font-bold" v-else>Client Phone</p>
              <p style="direction: ltr">
                {{ model.invoice.client.mobile }}
              </p>
            </div>
          </div>
          <div class="client-info mt-2">
            <div v-if="model.invoice.client.tax_number" class="client-info-item">
              <p class="font-bold">الرقم الضريبي</p>
              <p
                class="font-bold"
                v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
              >
                कर संख्या
              </p>
              <p
                class="font-bold"
                v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
              >
                ٹیکس نمبر
              </p>
              <p
                class="font-bold"
                v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
              >
                Vergi Numarası
              </p>
              <p class="font-bold" v-else>Tax number</p>
              <p>{{ model.invoice.client.tax_number }}</p>
            </div>
            <div v-if="model.invoice.client.commercial_register" class="client-info-item">
              <p class="font-bold">السجل التجاري</p>
              <p
                class="font-bold"
                v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
              >
                व्यावसायिक रजिस्टर
              </p>
              <p
                class="font-bold"
                v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
              >
                تجارتی رجسٹر
              </p>
              <p
                class="font-bold"
                v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
              >
                Ticari Sicil
              </p>
              <p class="font-bold" v-else>Commercial register</p>
              <p style="direction: ltr">
                {{ model.invoice.client.commercial_register }}
              </p>
            </div>
          </div>
        </div>

        <!-- Car Information for Car Care Module -->
        <div v-if="$helper.isCarCare() && model.car_info" class="mt-2">
          <table
            class="car-info-table w-full border-collapse border border-gray-300 text-xs"
          >
            <thead>
              <tr>
                <th
                  colspan="2"
                  class="border border-gray-300 px-2 py-1 bg-gray-50 text-center font-bold text-sm"
                >
                  معلومات السيارة
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >कार की जानकारी</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >کار کی معلومات</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Araç Bilgileri</span
                  >
                  <span v-else>Car Information</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td class="border border-gray-300 px-2 py-1 font-bold w-1/3 text-sm">
                  الماركة
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >ब्रांड</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >برانڈ</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Marka</span
                  >
                  <span v-else>Brand</span>
                </td>
                <td class="border border-gray-300 px-2 py-1 text-sm">
                  {{ model.car_info.brand }}
                </td>
              </tr>
              <tr>
                <td class="border border-gray-300 px-2 py-1 font-bold text-sm">
                  الموديل
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >मॉडल</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >ماڈل</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Model</span
                  >
                  <span v-else>Model</span>
                </td>
                <td class="border border-gray-300 px-2 py-1 text-sm">
                  {{ model.car_info.model }}
                </td>
              </tr>
              <tr>
                <td class="border border-gray-300 px-2 py-1 font-bold text-sm">
                  رقم اللوحة
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >प्लेट नंबर</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >پلیٹ نمبر</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Plaka Numarası</span
                  >
                  <span v-else>Plate Number</span>
                </td>
                <td class="border border-gray-300 px-2 py-1 text-sm">
                  {{ model.car_info.plate }}
                </td>
              </tr>
              <tr v-if="model.car_info.year">
                <td class="border border-gray-300 px-2 py-1 font-bold text-sm">
                  السنة
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >साल</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >سال</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Yıl</span
                  >
                  <span v-else>Year</span>
                </td>
                <td class="border border-gray-300 px-2 py-1 text-sm">
                  {{ model.car_info.year }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-if="model.invoice.items.length" class="invoice-items">
          <table>
            <thead>
              <tr>
                <th v-if="isValidAttribute('item_name')">الصنف</th>
                <th v-if="isValidAttribute('code')">كود الهدية</th>
                <th v-if="isValidAttribute('expiry')">تاريخ الانتهاء</th>
                <th v-if="isValidAttribute('service_name') || isValidAttribute('meal_name')">الخدمة</th>
                <th v-if="isValidAttribute('employee_name')">الموظف/ة</th>
                <th v-if="isValidAttribute('quantity')">الكمية</th>
                <th v-if="isValidAttribute('discount')">الخصم</th>
                <th v-if="isValidAttribute('total')">الاجمالي</th>
                <th v-if="isValidAttribute('date')">التاريخ</th>
                <th v-if="isValidAttribute('time')">الوقت</th>
                <th v-if="isValidAttribute('order') && hasOrders">الدور</th>
              </tr>
            </thead>
            <thead>
              <tr>
                <th v-if="isValidAttribute('item_name')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >वस्तु</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >آئٹم</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Ürün</span
                  >
                  <span v-else>Item</span>
                </th>
                <th v-if="isValidAttribute('code')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >गिफ्ट कार्ड कोड</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >گفٹ کارڈ کوڈ</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Hediye Kartı Kodu</span
                  >
                  <span v-else>Gift Card Code</span>
                </th>
                <th v-if="isValidAttribute('expiry')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >समाप्ति तिथि</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >ختم ہونے کی تاریخ</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Son Kullanma Tarihi</span
                  >
                  <span v-else>Expiry Date</span>
                </th>
                <th v-if="isValidAttribute('service_name') || isValidAttribute('meal_name')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >सेवा</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >سروس</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Hizmet</span
                  >
                  <span v-else>Service</span>
                </th>
                <th v-if="isValidAttribute('employee_name')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >कर्मचारी</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >ملازم</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Çalışan</span
                  >
                  <span v-else>Employee</span>
                </th>
                <th v-if="isValidAttribute('quantity')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >मात्रा</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >مقدار</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Miktar</span
                  >
                  <span v-else>Quantity</span>
                </th>
                <th v-if="isValidAttribute('discount')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >छूट</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >ڈسکاؤنٹ</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >İndirim</span
                  >
                  <span v-else>Discount</span>
                </th>
                <th v-if="isValidAttribute('total')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >कुल</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >کل</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Toplam</span
                  >
                  <span v-else>Price</span>
                </th>
                <th v-if="isValidAttribute('date')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >दिनांक</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >تاریخ</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Tarih</span
                  >
                  <span v-else>Date</span>
                </th>
                <th v-if="isValidAttribute('time')">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >समय</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >وقت</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Saat</span
                  >
                  <span v-else>Time</span>
                </th>
                <th v-if="isValidAttribute('order') && hasOrders">
                  <span v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)"
                    >क्रम</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >آرڈر</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Sıra</span
                  >
                  <span v-else>Order</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(item, index) in model.invoice.items">
                <td
                  v-for="tableData in Object.entries(item)"
                  :class="[
                    {
                      'text-center': ['quantity', 'total', 'order'].includes(
                        tableData[0]
                      ),
                    },
                    {
                      'whitespace-nowrap force-ltr': ['date', 'time', 'order', 'code', 'expiry'].includes(
                        tableData[0]
                      ),
                    },
                    {
                      hidden: !isValidAttribute(tableData[0]),
                    },
                    {
                      hidden: ['order', 'addons'].includes(tableData[0]) && !hasOrders,
                    },
                  ]"
                >
                  <!-- ! Display addons in item name for the restaurant module -->
                  <table
                    class="addons-table"
                    v-if="
                      $helper.isRestaurant(module) &&
                      tableData[0] === 'item_name' &&
                      (model.invoice.items[index]?.addons?.length ||
                        model.invoice.items[index]?.combos?.length)
                    "
                  >
                    <tr>
                      <td>
                        <div class="flex justify-between">
                          <p>{{ tableData[1] }}</p>
                          <p>
                            {{ model.invoice.items[index].meal_price }}
                          </p>
                        </div>
                        <p
                          class="addon-size"
                          v-for="combo in model.invoice.items[index]?.combos ?? []"
                        >
                          {{ combo.quantity }} X {{ combo.name }}
                        </p>
                      </td>
                    </tr>
                    <tr v-for="addon in model.invoice.items[index].addons">
                      <td class="addon-item addon-size">
                        {{ addon.attribute }}
                        {{ addon.option }}
                      </td>
                      <td class="addon-size text-center">
                        {{ addon.total }}
                      </td>
                    </tr>
                  </table>
                  <p v-else>
                    {{
                      tableData[0] === "total"
                        ? (item.total || item.total_tax || 0)
                        : tableData[0] === 'price'
                        ? (item.price || item.total || tableData[1])
                        : tableData[0] === 'service_name' || tableData[0] === 'meal_name'
                          ? (item.meal_name || item.service_name || tableData[1])
                          : tableData[1]
                    }}
                  </p>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="invoice-details">
          <div
            v-if="model.invoice?.pre_paid"
            class="invoice-details-item flex justify-between items-center"
          >
            <div class="flex items-center text-right">
              <div class="currency-area">
                <p>{{ model.branch?.currency?.ar }}</p>
                <p>{{ model.branch?.currency?.en }}</p>
              </div>
              <p class="price">{{ model.invoice.pre_paid }}</p>
            </div>
            <div class="invoice-item-title text-left">
              <p>الدفع المسبق</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                पूर्व भुगतान राशि
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                پری پیڈ رقم
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Ön Ödeme Tutarı
              </p>
              <p v-else>Pre Paid Amount</p>
            </div>
          </div>
          <div
            v-if="model.invoice?.price"
            class="invoice-details-item flex justify-between items-center"
          >
            <div class="flex items-center text-right">
              <div class="currency-area">
                <p>{{ model.branch?.currency?.ar }}</p>
                <p>{{ model.branch?.currency?.en }}</p>
              </div>
              <p class="price">{{ calculatedPriceBeforeTax }}</p>
            </div>
            <div class="invoice-item-title text-left">
              <p>الاجمالي قبل الضريبة</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                कर से पहले कुल
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ٹیکس سے پہلے کل
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Vergi Öncesi Toplam
              </p>
              <p v-else>Total Before Tax</p>
            </div>
          </div>
          <div
            v-if="model.invoice?.discount"
            class="invoice-details-item flex justify-between items-center"
          >
            <div class="flex items-center text-right">
              <div class="currency-area">
                <p>{{ model.branch?.currency?.ar }}</p>
                <p>{{ model.branch?.currency?.en }}</p>
              </div>
              <p class="price">{{ model.invoice.discount }}</p>
            </div>
            <div class="invoice-item-title text-left">
              <p>قيمة الخصم</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                छूट राशि
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ڈسکاؤنٹ رقم
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                İndirim Tutarı
              </p>
              <p v-else>Discount Amount</p>
            </div>
          </div>
          <div
            v-if="!model.invoice?.discount && model.invoice?.total_items_discount"
            class="invoice-details-item flex justify-between items-center"
          >
            <div class="flex items-center text-right">
              <div class="currency-area">
                <p>{{ model.branch?.currency?.ar }}</p>
                <p>{{ model.branch?.currency?.en }}</p>
              </div>
              <p class="price">{{ model.invoice.total_items_discount }}</p>
            </div>
            <div class="invoice-item-title text-left">
              <p>إجمالي خصم الأصناف</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">कुल आइटम छूट</p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                کل آئٹم ڈسکاؤنٹ
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Toplam Ürün İndirimi
              </p>
              <p v-else>Total Items Discount</p>
            </div>
          </div>
          <div
            v-if="model.invoice?.price_after_discount"
            class="invoice-details-item flex justify-between items-center"
          >
            <div class="flex items-center text-right">
              <div class="currency-area">
                <p>{{ model.branch?.currency?.ar }}</p>
                <p>{{ model.branch?.currency?.en }}</p>
              </div>
              <p class="price">
                {{ model.invoice.price_after_discount }}
              </p>
            </div>
            <div class="invoice-item-title text-left">
              <p>الاجمالي بعد الخصم</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                छूट के बाद कुल
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ڈسکاؤنٹ کے بعد کل
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                İndirim Sonrası Toplam
              </p>
              <p v-else>Total After Discount</p>
            </div>
          </div>
          <div
            v-if="model.invoice?.tax"
            class="invoice-details-item flex justify-between items-center"
          >
            <div class="flex items-center text-right">
              <div class="currency-area">
                <p>{{ model.branch?.currency?.ar }}</p>
                <p>{{ model.branch?.currency?.en }}</p>
              </div>
              <p class="price">{{ model.invoice.tax }}</p>
            </div>
            <div class="invoice-item-title text-left">
              <p>قيمة الضريبة</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">कर राशि</p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ٹیکس رقم
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Vergi Tutarı
              </p>
              <p v-else>Tax Amount</p>
            </div>
          </div>
          <div
            v-if="model.invoice?.total"
            class="invoice-details-item flex justify-between items-center"
          >
            <div class="flex items-center text-right">
              <div class="currency-area">
                <p>{{ model.branch?.currency?.ar }}</p>
                <p>{{ model.branch?.currency?.en }}</p>
              </div>
              <p class="price">{{ model.invoice.total }}</p>
            </div>
            <div class="invoice-item-title text-left">
              <p>الاجمالي بعد الضريبة</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                कर के बाद कुल
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ٹیکس کے بعد کل
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Vergi Sonrası Toplam
              </p>
              <p v-else>Total After Tax</p>
            </div>
          </div>
          <div
            v-if="model.invoice?.payment_methods"
            class="invoice-details-item flex justify-between items-center"
          >
            <div class="w-7/12">
              <p class="price">
                {{ model.invoice.payment_methods }}
              </p>
            </div>
            <div class="invoice-item-title text-left">
              <p>طرق الدفع</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
                भुगतान विधियां
              </p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                ادائیگی کے طریقے
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Ödeme Yöntemleri
              </p>
              <p v-else>Payment Methods</p>
            </div>
          </div>
        </div>
      </section>
      <footer class="invoice-details">
        <div class="flex justify-center">
          <img v-if="model.qr_image" :src="model.qr_image" />
        </div>
        <div class="invoice-details-item">
          <p class="invoice-title" style="border-bottom: 0">
            {{ $t("base.policy") }}
          </p>
          <div style="white-space: pre-wrap" class="pb-2" v-html="model.policy"></div>
        </div>
        <div class="mt-2">
          <p>شكرا لثقتكم بنا</p>
          <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
            हम पर विश्वास करने के लिए धन्यवाद
          </p>
          <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
            ہم پر اعتماد کرنے کا شکریہ
          </p>
          <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
            Bize güveniniz için teşekkür ederiz
          </p>
          <p v-else>Thank you for trusting us</p>
          <p>برنامج هيرموسا المحاسبي المتكامل</p>
          <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">
            एकीकृत लेखांकन कार्यक्रम हर्मोसा
          </p>
          <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
            ہرموسا انٹیگریٹڈ اکاؤنٹنگ پروگرام
          </p>
          <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
            Entegre Muhasebe Programı Hermosa
          </p>
          <p v-else>Integrated Accounting Program Hermosa</p>
          <p>{{ websiteUrl }}</p>
        </div>
      </footer>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, defineExpose } from "vue";
import LabelButton from "../label/LabelButton.vue";
import helper from "../../helper";
import FormHelper from "../../helper/FormHelper";

const currentLocale = computed(() => helper.getLocale());
const isHindiLanguage = computed(() => currentLocale.value === "hi");
const isUrduLanguage = computed(() => currentLocale.value === "ur");
const isTurkishLanguage = computed(() => currentLocale.value === "tr");

// Invoice language settings from API with caching
const invoiceLanguageSettings = ref(null);

// Cache key for localStorage
const INVOICE_LANGUAGE_CACHE_KEY = "invoice_language_settings";

// Get cached settings from localStorage
const getCachedSettings = () => {
  try {
    const cached = localStorage.getItem(INVOICE_LANGUAGE_CACHE_KEY);
    if (cached) {
      const parsed = JSON.parse(cached);
      // Check if cache is still valid (cache for 5 minutes)
      if (Date.now() - parsed.timestamp < 5 * 60 * 1000) {
        return parsed.data;
      }
    }
  } catch (error) {
    console.error("Error reading cached settings:", error);
  }
  return null;
};

// Cache settings in localStorage
const cacheSettings = (settings) => {
  try {
    localStorage.setItem(
      INVOICE_LANGUAGE_CACHE_KEY,
      JSON.stringify({
        data: settings,
        timestamp: Date.now(),
      })
    );
  } catch (error) {
    console.error("Error caching settings:", error);
  }
};

// Clear cache (can be called from settings page when settings are updated)
const clearInvoiceLanguageCache = () => {
  try {
    localStorage.removeItem(INVOICE_LANGUAGE_CACHE_KEY);
    invoiceLanguageSettings.value = null;
  } catch (error) {
    console.error("Error clearing cache:", error);
  }
};

// Expose clear cache function globally for settings page
if (typeof window !== "undefined") {
  window.clearInvoiceLanguageCache = clearInvoiceLanguageCache;
}

// Fetch invoice language settings from API with caching
const fetchInvoiceLanguageSettings = async () => {
  try {
    // First check cache
    const cached = getCachedSettings();
    if (cached) {
      invoiceLanguageSettings.value = cached;
      return;
    }

    const branchId = helper.getBranchId();
    if (branchId) {
      const response = await FormHelper.get(`seller/branches/${branchId}/settings`);
      let settings = null;

      // API response has double nesting: response.data.data.invoice_language
      if (response.data?.data?.invoice_language) {
        settings = response.data.data.invoice_language;
      } else if (response.data?.invoice_language) {
        // Fallback for different response structures
        settings = response.data.invoice_language;
      }

      if (settings) {
        invoiceLanguageSettings.value = settings;
        cacheSettings(settings);
      }
    }
  } catch (error) {
    console.error("Error fetching invoice language settings:", error);
  }
};

// Get invoice language settings with fallback
const invoiceLanguage = computed(() => {
  // Use API settings if available, otherwise fallback to defaults
  if (invoiceLanguageSettings.value) {
    return invoiceLanguageSettings.value;
  }
  return {
    primary: currentLocale.value || "ar",
    secondary: "en",
    allow_secondary: true,
  };
});

const primaryLanguage = computed(() => invoiceLanguage.value.primary || "ar");
const secondaryLanguage = computed(() => invoiceLanguage.value.secondary || "en");
const allowSecondary = computed(() => invoiceLanguage.value.allow_secondary !== false);

// Language detection helpers based on invoice settings
const isPrimaryHindi = computed(() => primaryLanguage.value === "hi");
const isPrimaryUrdu = computed(() => primaryLanguage.value === "ur");
const isPrimaryTurkish = computed(() => primaryLanguage.value === "tr");
const isPrimaryArabic = computed(() => primaryLanguage.value === "ar");
const isPrimaryEnglish = computed(() => primaryLanguage.value === "en");

const isSecondaryHindi = computed(() => secondaryLanguage.value === "hi");
const isSecondaryUrdu = computed(() => secondaryLanguage.value === "ur");
const isSecondaryTurkish = computed(() => secondaryLanguage.value === "tr");
const isSecondaryArabic = computed(() => secondaryLanguage.value === "ar");
const isSecondaryEnglish = computed(() => secondaryLanguage.value === "en");

// Display language logic
const displayLanguages = computed(() => {
  const languages = [primaryLanguage.value];
  if (allowSecondary.value && secondaryLanguage.value !== primaryLanguage.value) {
    languages.push(secondaryLanguage.value);
  }
  return languages;
});

// Helper function to get language text based on settings
const getLanguageText = (hindiText, urduText, turkishText, englishText) => {
  let text = "";
  if (isPrimaryHindi.value) text += hindiText;
  else if (isPrimaryUrdu.value) text += urduText;
  else if (isPrimaryTurkish.value) text += turkishText;
  else if (isPrimaryEnglish.value) text += englishText;
  else text += englishText; // default to english

  if (allowSecondary.value && secondaryLanguage.value !== primaryLanguage.value) {
    text += "\n";
    if (isSecondaryHindi.value) text += hindiText;
    else if (isSecondaryUrdu.value) text += urduText;
    else if (isSecondaryTurkish.value) text += turkishText;
    else if (isSecondaryEnglish.value) text += englishText;
    else text += englishText;
  }
  return text;
};

const props = defineProps({
  id: {
    required: false,
    type: String,
    default: "pdf-container",
  },
  hasOrders: Boolean,
  model: Object,
  kind: {
    type: String,
    validator(value) {
      return [
        "simplified",
        "debitNote",
        "simplified_b2b",
        "debitNote_b2b",
        "refundSalesInvoice",
        "deposit",
        "depositRefund",
        "usedProducts",
        "sessions",
      ].includes(value);
    },
  },
});

const title = ref({ text: "", textAlt: "" });
const websiteUrl = location.origin;

const calculatedPriceBeforeTax = computed(() => {
  // For gift cards or invoices where items don't have total, use invoice.price directly
  if (!props.model.invoice?.items?.length) {
    return props.model.invoice?.price || 0;
  }

  // Check if items have total field (gift card items don't have total)
  const firstItem = props.model.invoice.items[0];
  if (firstItem && !('total' in firstItem)) {
    return props.model.invoice?.price || 0;
  }

  return props.model.invoice.items
    .reduce((total, item) => {
      // Use item.price (before tax) if available, otherwise fall back to item.total
      const itemSubtotal = parseFloat(item.price || item.total || 0);
      return total + itemSubtotal;
    }, 0)
    .toFixed(2);
});

switch (props.kind) {
  case "simplified":
    if (isPrimaryHindi.value) {
      title.value.text = "सरलीकृत कर इनवॉइस";
      title.value.textAlt = "الفاتورة الضريبية المبسطة";
    } else if (isPrimaryUrdu.value) {
      title.value.text = "سادہ ٹیکس انوائس";
      title.value.textAlt = "الفاتورة الضريبية المبسطة";
    } else if (isPrimaryTurkish.value) {
      title.value.text = "Basitleştirilmiş Vergi Faturası";
      title.value.textAlt = "الفاتورة الضريبية المبسطة";
    } else {
      title.value.text = "Simplified Tax Invoice";
      title.value.textAlt = "الفاتورة الضريبية المبسطة";
    }
    break;

  case "simplified_b2b":
    if (isPrimaryHindi.value) {
      title.value.text = "कर इनवॉइस";
      title.value.textAlt = "فاتورة ضريبية";
    } else if (isPrimaryUrdu.value) {
      title.value.text = "ٹیکس انوائس";
      title.value.textAlt = "فاتورة ضريبية";
    } else if (isPrimaryTurkish.value) {
      title.value.text = "Vergi Faturası";
      title.value.textAlt = "فاتورة ضريبية";
    } else {
      title.value.text = "Tax Invoice";
      title.value.textAlt = "فاتورة ضريبية";
    }
    break;

  case "refundSalesInvoice":
    title.value.text = "إشعار دائن";
    title.value.textAlt = "الفاتورة الضريبية المبسطة";
    break;

  case "debitNote":
    title.value.text = "إشعار مدين";
    title.value.textAlt = "الفاتورة الضريبية المبسطة";
    break;

  case "debitNote_b2b":
    title.value.text = "إشعار مدين";
    title.value.textAlt = "الفاتورة الضريبية";
    break;

  case "deposit":
    title.value.text = "الفاتورة الضريبية المبسطة";
    title.value.textAlt = "( فاتورة العربون )";
    break;

  case "depositRefund":
    title.value.text = "إشعار دائن";
    title.value.textAlt = "( فاتورة العربون )";
    break;

  case "usedProducts":
    if (isPrimaryHindi.value) {
      title.value.text = "उपयोग किए गए उत्पाद इनवॉइस";
      title.value.textAlt = "فاتورة استخدام منتجات";
    } else if (isPrimaryUrdu.value) {
      title.value.text = "استعمال شدہ مصنوعات انوائس";
      title.value.textAlt = "فاتورة استخدام منتجات";
    } else if (isPrimaryTurkish.value) {
      title.value.text = "Kullanılmış Ürünler Faturası";
      title.value.textAlt = "فاتورة استخدام منتجات";
    } else {
      title.value.text = "Used Products Invoice";
      title.value.textAlt = "فاتورة استخدام منتجات";
    }
    break;

  case "sessions":
    if (isPrimaryHindi.value) {
      title.value.text = "सत्र बुकिंग";
      title.value.textAlt = "حجوزات الجلسات";
    } else if (isPrimaryUrdu.value) {
      title.value.text = "سیشن بکنگ";
      title.value.textAlt = "حجوزات الجلسات";
    } else if (isPrimaryTurkish.value) {
      title.value.text = "Oturum Rezervasyonları";
      title.value.textAlt = "حجوزات الجلسات";
    } else {
      title.value.text = "Sessions Bookings";
      title.value.textAlt = "حجوزات الجلسات";
    }
    break;
}

const printArea = ref(null);
const emit = defineEmits(["area"]);
// Fetch settings on component mount
onMounted(() => {
  fetchInvoiceLanguageSettings();

  // Listen for localStorage changes (when settings are updated in another tab)
  const handleStorageChange = (event) => {
    if (event.key === INVOICE_LANGUAGE_CACHE_KEY) {
      try {
        const newData = JSON.parse(event.newValue);
        if (newData && newData.data) {
          invoiceLanguageSettings.value = newData.data;
        }
      } catch (error) {
        console.error("Error parsing updated localStorage data:", error);
      }
    }
  };

  window.addEventListener("storage", handleStorageChange);
  emit("area", printArea.value);

  // Cleanup on unmount
  onUnmounted(() => {
    window.removeEventListener("storage", handleStorageChange);
  });
});

const printInvoice = async () => {
  document.getElementById("print-container").innerHTML = printArea.value.innerHTML;
  window.print();
};

const isValidAttribute = (key) =>
  key != "addons" ? props.model.invoice?.fields.includes(key) : false;
</script>
