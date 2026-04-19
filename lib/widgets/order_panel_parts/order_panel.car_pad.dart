// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_panel.dart';

extension OrderPanelCarPad on _OrderPanelState {
  Future<void> _openCarNumberPad() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        var value = widget.carNumberController.text.trim();
        var useArabic = _carPadArabicLetters;

        const englishLetters = <String>[
          'A',
          'B',
          'C',
          'D',
          'E',
          'F',
          'G',
          'H',
          'I',
          'J',
          'K',
          'L',
          'M',
          'N',
          'O',
          'P',
          'Q',
          'R',
          'S',
          'T',
          'U',
          'V',
          'W',
          'X',
          'Y',
          'Z',
        ];
        const arabicLetters = <String>[
          'ا',
          'ب',
          'ت',
          'ث',
          'ج',
          'ح',
          'خ',
          'د',
          'ر',
          'س',
          'ص',
          'ط',
          'ع',
          'ف',
          'ق',
          'ك',
          'ل',
          'م',
          'ن',
          'ه',
          'و',
          'ي',
        ];
        const digits = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9'];

        return StatefulBuilder(
          builder: (context, setModalState) {
            void append(String token) {
              if (value.length >= 18) return;
              setModalState(() => value = '$value$token');
            }

            void removeLast() {
              if (value.isEmpty) return;
              setModalState(() => value = value.substring(0, value.length - 1));
            }

            Widget buildKey(
              String label, {
              VoidCallback? onTap,
              Color? color,
              Color? textColor,
              IconData? icon,
            }) {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color ?? const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: icon != null
                      ? Icon(icon, size: 18, color: textColor ?? Colors.black87)
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textColor ?? Colors.black87,
                          ),
                        ),
                ),
              );
            }

            final letterSet = useArabic ? arabicLetters : englishLetters;
            final size = MediaQuery.of(context).size;
            final isTablet = size.shortestSide >= 600;

            Widget buildHeader() {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      _tr('رقم السيارة', 'Car Number'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_tr('إغلاق', 'Close')),
                  ),
                ],
              );
            }

            Widget buildValueBox() {
              return Container(
                height: 52,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.car, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        value.isEmpty
                            ? _tr('ادخل رقم السيارة', 'Enter car number')
                            : value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: value.isEmpty
                              ? const Color(0xFF94A3B8)
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget buildActionsRow() {
              return Row(
                children: [
                  Expanded(
                    child: buildKey(
                      useArabic ? 'AR' : 'EN',
                      onTap: () => setModalState(() {
                        useArabic = !useArabic;
                        _carPadArabicLetters = useArabic;
                      }),
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildKey('-', onTap: () => append('-')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildKey(
                      '',
                      icon: Icons.backspace_outlined,
                      onTap: removeLast,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildKey(
                      _tr('مسح', 'Clear'),
                      onTap: () => setModalState(() => value = ''),
                      color: const Color(0xFFFEE2E2),
                      textColor: const Color(0xFFB91C1C),
                    ),
                  ),
                ],
              );
            }

            Widget buildDigitsGrid() {
              return GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.8,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  ...digits.map((d) => buildKey(d, onTap: () => append(d))),
                  buildKey('0', onTap: () => append('0')),
                  buildKey(
                    _tr('تم', 'Done'),
                    onTap: () => Navigator.pop(context, value),
                    color: const Color(0xFF10B981),
                    textColor: Colors.white,
                  ),
                  buildKey(
                    _tr('حفظ', 'Save'),
                    onTap: () => Navigator.pop(context, value),
                    color: const Color(0xFFF58220),
                    textColor: Colors.white,
                  ),
                ],
              );
            }

            Widget buildLetters() {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: letterSet
                    .map(
                      (letter) => SizedBox(
                        width: 48,
                        child: buildKey(letter, onTap: () => append(letter)),
                      ),
                    )
                    .toList(growable: false),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: isTablet
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildHeader(),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      buildValueBox(),
                                      const SizedBox(height: 12),
                                      buildActionsRow(),
                                      const SizedBox(height: 10),
                                      buildDigitsGrid(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: buildLetters(),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildHeader(),
                            const SizedBox(height: 8),
                            buildValueBox(),
                            const SizedBox(height: 12),
                            buildActionsRow(),
                            const SizedBox(height: 10),
                            buildDigitsGrid(),
                            const SizedBox(height: 10),
                            buildLetters(),
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      widget.carNumberController.text = result.trim();
      setState(() {});
    }
  }
}
