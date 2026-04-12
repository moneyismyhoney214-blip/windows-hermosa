<template>
  <LabelButton
    id="print-chicken"
    :btnTitle="
      $helper.isRestaurant(module)
        ? $t('base.print_reservation')
        : $t('base.print_orders')
    "
    type="print"
    @click="printInvoice"
  />

  <div ref="printArea" class="hidden">
    <div class="bill bill-container size-8cm">
      <header>
        <div class="seller-info">
          <div class="info-top">
            <div class="info">
              <!-- <p class="title font-bold">
                                {{ model.branch.seller_name }}
                            </p> -->
              <p>{{ model.branch.address }}</p>
              <p v-if="model.branch.mobile" class="mobile">
                {{ model.branch.mobile }}
              </p>
              <p v-if="model.branch.telephone" class="mobile">
                {{ model.branch.telephone }}
              </p>
            </div>
            <div class="logo">
              <img :src="model.branch.seller.logo" alt="" />
              <!-- <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/24/LEGO_logo.svg/2048px-LEGO_logo.svg.png" alt=""> -->
            </div>
          </div>
          <div class="info-bottom">
            <div v-if="model.invoice?.cashier" class="info-bottom-item">
              <p>الكاشير</p>
              <p>{{ model.invoice?.cashier?.fullname }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">कैशियर</p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                کیشیئر
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Kasiyer
              </p>
              <p v-else>Cashier</p>
            </div>
            <div class="info-bottom-item font-bold">
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
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Sipariş Türü
              </p>
              <p v-else>order type</p>
            </div>
            <div class="flex justify-center my-2">
              <div class="border-2 border-black px-4 py-1 text-lg font-bold force-ltr">
                # Order: {{ model.order_number }}
              </div>
            </div>
            <div class="flex justify-center my-1">
              <div class="border-2 border-black px-4 py-1 text-base font-bold force-ltr">
                 {{ model.invoice.invoice_number }}
              </div>
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
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Masa Numarası
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
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Araç Numarası
              </p>
              <p v-else>car number</p>
            </div>
            <div class="info-bottom-item">
              <p>التاريخ</p>
              <p>{{ model.invoice.date }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">दिनांक</p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">
                تاریخ
              </p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Tarih
              </p>
              <p v-else>Date</p>
            </div>
            <div class="info-bottom-item">
              <p>الوقت</p>
              <p class="force-ltr">{{ model.invoice.time }}</p>
              <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">समय</p>
              <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">وقت</p>
              <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">
                Saat
              </p>
              <p v-else>Time</p>
            </div>
          </div>
        </div>
      </header>
      <section>
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

        <div v-if="model.invoice.items.length" class="invoice-items">
          <table>
            <thead>
              <tr>
                <th v-if="isValidAttribute('item_name')">الصنف</th>
                <th v-if="isValidAttribute('service_name')">الخدمة</th>
                <th v-if="isValidAttribute('employee_name')">الموظف/ة</th>
                <th v-if="isValidAttribute('quantity')">الكمية</th>
                <th v-if="isValidAttribute('discount')">الخصم</th>
                <th v-if="isValidAttribute('total')">السعر</th>
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
                <th v-if="isValidAttribute('service_name')">
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
                    >मूल्य</span
                  >
                  <span v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)"
                    >قیمت</span
                  >
                  <span v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)"
                    >Fiyat</span
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
                      'whitespace-nowrap force-ltr': ['date', 'time', 'order'].includes(
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
                      model.invoice.items[index].addons.length
                    "
                  >
                    <tr>
                      <td colspan="2">
                        {{ tableData[1] }}
                      </td>
                    </tr>
                    <tr v-for="addon in model.invoice.items[index].addons">
                      <td class="addon-item addon-size" colspan="2">
                        {{ addon.attribute }}
                        {{ addon.option }}
                      </td>
                    </tr>
                  </table>
                  <p v-else>{{ tableData[1] }}</p>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div v-if="model.booking?.notes" class="notes-section">
          <div class="notes-title">
            <p>ملاحظات</p>
            <p v-if="isPrimaryHindi || (allowSecondary && isSecondaryHindi)">टिप्पणियाँ</p>
            <p v-else-if="isPrimaryUrdu || (allowSecondary && isSecondaryUrdu)">نوٹس</p>
            <p v-else-if="isPrimaryTurkish || (allowSecondary && isSecondaryTurkish)">Notlar</p>
            <p v-else>Notes</p>
          </div>
          <div class="notes-content">
            <p>{{ model.booking.notes }}</p>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from "vue";
import LabelButton from "../label/LabelButton.vue";
import helper from "../../helper";
import FormHelper from "../../helper/FormHelper";
import { connectWebSocket, sendPrintRequest } from "../../helper/websocketHelper";

const branchId = helper.getBranchId();
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
  hasOrders: Boolean,
  model: {
    type: Object,
    required: true,
    default: () => ({
      invoice: {
        items: [],
        categories: [],
      },
    }),
  },
  buttonTitle: {
    type: String,
    default: "",
  },
  kind: {
    type: String,
    validator(value) {
      return [
        "simplified",
        "simplified_b2b",
        "refundSalesInvoice",
        "deposit",
        "depositRefund",
        "usedProducts",
        "sessions",
      ].includes(value);
    },
  },
  module: {
    type: String,
    default: "",
  },
});

const title = ref({ text: "", textAlt: "" });
const websiteUrl = location.origin;
const printArea = ref(null);
const arePrintersActive = ref(false);
const settingOfPrinters = ref({});
// Fetch settings on component mount
onMounted(async () => {
  await FormHelper.getSetting(branchId).then((res) => {
    settingOfPrinters.value = res.printers;
  });
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

  // Cleanup on unmount
  onUnmounted(() => {
    window.removeEventListener("storage", handleStorageChange);
  });
});

// Update title based on kind and language settings
const updateTitle = () => {
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
};

// Watch for language changes and update title accordingly
watch(
  [isPrimaryHindi, isPrimaryUrdu, isPrimaryEnglish, props.kind],
  () => {
    updateTitle();
  },
  { immediate: true }
);

const isValidAttribute = (key) =>
  key != "addons" ? props.model.invoice?.fields.includes(key) : false;

// Function to print the invoice using WebSocket
const printInvoice = async () => {
  // Update print count
  let form = {};
  if (settingOfPrinters.value.active) {
    form = {
      booking_id: props.model.booking?.id,
      print_again: true,
    };
  }
  if (props.model.booking?.id) {
    try {
      FormHelper.patch(
        `seller/booking/update-print-count/${props.model.booking.id}`,
        form
      ).then(async (response) => {
        if (settingOfPrinters.value.active) {
          await connectWebSocket(null, 9393, settingOfPrinters.value.link);
          await response.data.files.map(async (object) => {
            sendPrintRequest(object.url, object.printer);
          });
          await sendPrintRequest(response.data.receipt, settingOfPrinters.value.recipt_printer);
        }
      });
    } catch (error) {
      console.error("Failed to update print count:", error);
    }
  }

  // Check if printers are active in branch settings
  const branchData = localStorage.getItem("branch");
  if (branchData) {
    const parsedBranch = JSON.parse(branchData);
    if (parsedBranch.printers_settings.active === false) {
      arePrintersActive.value = false;
    } else {
      arePrintersActive.value = true;
    }
  }
  document.getElementById("print-container").innerHTML = printArea.value.innerHTML;
  window.print();
  return;
};
</script>

<style scoped>
.bill-container {
  /* font-size: 14px !important; Removed to inherit global */
}

.seller-info .info-top .info p,
.seller-info .info-bottom .info-bottom-item p {
  font-size: 18px !important;
  line-height: 1.5 !important;
}

.seller-info .border-2 {
  font-size: 20px !important;
  font-weight: bold !important;
}

.client-info .client-info-item p {
  font-size: 18px !important;
  line-height: 1.4 !important;
}

.invoice-items table thead th {
  font-size: 20px !important;
  font-weight: bold !important;
  padding: 6px !important;
}

.invoice-items table tbody td p {
  font-size: 18px !important;
  line-height: 1.4 !important;
}

.addons-table td {
  font-size: 16px !important;
  padding: 4px !important;
}

.addon-item {
  font-size: 16px !important;
}

.invoice-title p {
  font-size: 22px !important;
  font-weight: bold !important;
}

.notes-section {
  margin-top: 10px !important;
  border: 2px solid #000 !important;
  border-radius: 4px !important;
  overflow: hidden !important;
}

.notes-title {
  background-color: #f0f0f0 !important;
  padding: 4px 8px !important;
  border-bottom: 2px solid #000 !important;
  display: flex !important;
  justify-content: space-between !important;
  align-items: center !important;
}

.notes-title p {
  font-size: 18px !important;
  font-weight: bold !important;
  margin: 0 !important;
}

.notes-content {
  padding: 8px !important;
  background-color: #fff !important;
}

.notes-content p {
  font-size: 17px !important;
  line-height: 1.5 !important;
  margin: 0 !important;
  white-space: pre-wrap !important;
  word-wrap: break-word !important;
}
</style>
