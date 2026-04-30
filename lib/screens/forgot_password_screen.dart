import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../services/api/auth_service.dart';
import '../services/language_service.dart';

/// Three-step mobile-based password-reset flow. Adapts its layout to four
/// form factors (phone / Sunmi / tablet / desktop) and keeps the OTP step
/// on an in-screen numpad so the keyboard never steals half the viewport.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _ForgotStep { mobile, code, reset, done }

enum _Layout { compact, medium, wide }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _kPrimary = Color(0xFFF58220);
  static const _kBg = Color(0xFFF7F8FB);
  static const _kSurface = Colors.white;
  static const _kBorder = Color(0xFFE6E8EF);
  static const _kTextDark = Color(0xFF0F172A);
  static const _kTextMuted = Color(0xFF64748B);
  static const _kDanger = Color(0xFFDC2626);
  static const _kSuccess = Color(0xFF16A34A);

  static const int _otpLength = 6;

  final AuthService _auth = getIt<AuthService>();

  String _otp = '';
  final _mobileCtrl = TextEditingController();
  final _mobileFormKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _resetFormKey = GlobalKey<FormState>();

  _ForgotStep _step = _ForgotStep.mobile;
  bool _busy = false;
  String? _error;

  String? _checkRoute;
  String? _resetRoute;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLangChanged);
  }

  @override
  void dispose() {
    translationService.removeListener(_onLangChanged);
    _mobileCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  String _tr(String key) => translationService.t(key);

  String _l({
    required String ar,
    required String en,
    String? es,
    String? tr,
    String? hi,
    String? ur,
  }) {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    switch (code) {
      case 'ar':
        return ar;
      case 'es':
        return es ?? en;
      case 'tr':
        return tr ?? en;
      case 'hi':
        return hi ?? en;
      case 'ur':
        return ur ?? en;
      case 'en':
      default:
        return en;
    }
  }

  _Layout _layoutFor(Size size) {
    if (size.width >= 1100) return _Layout.wide;
    if (size.width >= 640) return _Layout.medium;
    return _Layout.compact;
  }

  // ─────────────────── Numpad (OTP only) ───────────────────

  void _onPadDigit(String d) {
    if (_busy || _step != _ForgotStep.code) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      if (_otp.length < _otpLength) _otp += d;
    });
    if (_otp.length == _otpLength) {
      Future.microtask(_submitCode);
    }
  }

  void _onPadBackspace() {
    if (_busy || _step != _ForgotStep.code || _otp.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _otp = _otp.substring(0, _otp.length - 1);
    });
  }

  void _onPadClear() {
    if (_busy || _step != _ForgotStep.code) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _error = null;
      _otp = '';
    });
  }

  // ─────────────────── Step submissions ───────────────────

  Future<void> _submitMobile() async {
    if (!_mobileFormKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final route = await _auth.sendForgotPasswordCode(_mobileCtrl.text);
      _checkRoute = route;
      if (!mounted) return;
      setState(() {
        _step = _ForgotStep.code;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  Future<void> _submitCode() async {
    if (_otp.length < _otpLength) {
      setState(() => _error = _l(
            ar: 'أدخل الرمز المكون من 6 أرقام',
            en: 'Enter the 6-digit code',
            es: 'Ingresa el código de 6 dígitos',
            tr: '6 haneli kodu girin',
            hi: '6 अंकों का कोड दर्ज करें',
            ur: '6 ہندسوں کا کوڈ درج کریں',
          ));
      return;
    }
    final route = _checkRoute;
    if (route == null) {
      setState(() => _error = _l(
            ar: 'انتهت الجلسة، أعد إرسال الرمز',
            en: 'Session expired, please request a new code',
            es: 'La sesión expiró, solicita un nuevo código',
            tr: 'Oturum doldu, yeni kod iste',
            hi: 'सत्र समाप्त, नया कोड भेजें',
            ur: 'سیشن ختم ہوگیا، نیا کوڈ بھیجیں',
          ));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nextRoute =
          await _auth.checkResetCode(signedRoute: route, otp: _otp);
      _resetRoute = nextRoute;
      if (!mounted) return;
      setState(() {
        _step = _ForgotStep.reset;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _otp = '';
        _busy = false;
      });
    }
  }

  Future<void> _submitReset() async {
    if (!_resetFormKey.currentState!.validate()) return;
    final route = _resetRoute;
    if (route == null) {
      setState(() => _error = _l(
            ar: 'انتهت الجلسة، أعد المحاولة',
            en: 'Session expired, please try again',
            es: 'La sesión expiró, inténtalo de nuevo',
            tr: 'Oturum doldu, tekrar deneyin',
            hi: 'सत्र समाप्त, पुनः प्रयास करें',
            ur: 'سیشن ختم ہوگیا، دوبارہ کوشش کریں',
          ));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.resetForgottenPassword(
        signedRoute: route,
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _step = _ForgotStep.done;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  // ─────────────────── Root ───────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          translationService.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: LayoutBuilder(builder: (ctx, constraints) {
            final layout = _layoutFor(constraints.biggest);
            final maxW = switch (layout) {
              _Layout.compact => double.infinity,
              _Layout.medium => 560.0,
              _Layout.wide => 920.0,
            };
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: layout == _Layout.compact ? 16 : 24,
                vertical: 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _topBar(layout),
                      const SizedBox(height: 16),
                      _stepIndicator(),
                      const SizedBox(height: 20),
                      _buildStep(layout),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _topBar(_Layout layout) {
    return Row(
      children: [
        _iconButton(
          icon: translationService.isRTL
              ? LucideIcons.arrowRight
              : LucideIcons.arrowLeft,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _tr('forgot_password'),
            style: GoogleFonts.cairo(
              color: _kTextDark,
              fontSize: layout == _Layout.compact ? 17 : 19,
              fontWeight: FontWeight.w800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _iconButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: _kTextDark),
        ),
      ),
    );
  }

  Widget _stepIndicator() {
    final active = switch (_step) {
      _ForgotStep.mobile => 0,
      _ForgotStep.code => 1,
      _ForgotStep.reset => 2,
      _ForgotStep.done => 3,
    };
    return Row(
      children: List.generate(3, (i) {
        final done = i < active;
        final isActive = i == active;
        return Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: i < 2 ? 8 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: done || isActive ? _kPrimary : _kBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStep(_Layout layout) {
    switch (_step) {
      case _ForgotStep.mobile:
        return _buildMobileStep(layout);
      case _ForgotStep.code:
        return _buildCodeStep(layout);
      case _ForgotStep.reset:
        return _buildResetStep(layout);
      case _ForgotStep.done:
        return _buildDoneStep();
    }
  }

  // ─────────────────── Step 1: mobile ───────────────────

  Widget _buildMobileStep(_Layout layout) {
    return _card(
      child: Form(
        key: _mobileFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              LucideIcons.keyRound,
              _l(
                ar: 'استعادة كلمة المرور',
                en: 'Recover Password',
                es: 'Recuperar Contraseña',
                tr: 'Şifre Kurtarma',
                hi: 'पासवर्ड रिकवर',
                ur: 'پاس ورڈ بحالی',
              ),
              _l(
                ar: 'أدخل بريدك الإلكتروني أو رقم جوالك لإرسال رمز التحقق',
                en: 'Enter your email or mobile number to receive a verification code',
                es: 'Ingresa tu correo o número de móvil para recibir un código',
                tr: 'Doğrulama kodu için e-posta veya cep numaranızı girin',
                hi: 'सत्यापन कोड के लिए अपना ईमेल या मोबाइल नंबर दर्ज करें',
                ur: 'تصدیقی کوڈ کیلئے ای میل یا موبائل نمبر درج کریں',
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _mobileCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.telephoneNumber,
              ],
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              inputFormatters: [
                LengthLimitingTextInputFormatter(120),
              ],
              onFieldSubmitted: (_) => _submitMobile(),
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _kTextDark,
              ),
              decoration: _fieldDecoration(
                label: _l(
                  ar: 'البريد الإلكتروني أو رقم الجوال',
                  en: 'Email or mobile number',
                ),
                hint: 'name@example.com',
                icon: LucideIcons.atSign,
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) {
                  return _l(
                    ar: 'البريد الإلكتروني أو رقم الجوال مطلوب',
                    en: 'Email or mobile number required',
                  );
                }
                final isEmail = t.contains('@');
                if (isEmail) {
                  // Minimal email shape — backend will do the real lookup.
                  final emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!emailRe.hasMatch(t)) {
                    return _l(
                      ar: 'بريد إلكتروني غير صحيح',
                      en: 'Invalid email address',
                    );
                  }
                  return null;
                }
                final digits = t.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 7) {
                  return _l(
                    ar: 'رقم جوال غير صحيح',
                    en: 'Invalid mobile number',
                  );
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _errorBanner(_error!),
            ],
            const SizedBox(height: 20),
            _primaryButton(
              label: _l(
                ar: 'إرسال رمز التحقق',
                en: 'Send Verification Code',
                es: 'Enviar Código',
                tr: 'Kodu Gönder',
                hi: 'कोड भेजें',
                ur: 'کوڈ بھیجیں',
              ),
              icon: LucideIcons.send,
              onPressed: _submitMobile,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────── Step 2: OTP ───────────────────

  Widget _buildCodeStep(_Layout layout) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          LucideIcons.shieldCheck,
          _l(
            ar: 'تأكيد الرمز',
            en: 'Verify Code',
            es: 'Verificar Código',
            tr: 'Kodu Doğrula',
            hi: 'कोड सत्यापित करें',
            ur: 'کوڈ کی تصدیق',
          ),
          _l(
            ar: 'أدخل الرمز المرسل إلى جوالك',
            en: 'Enter the code sent to your mobile',
            es: 'Ingresa el código enviado a tu móvil',
            tr: 'Cep telefonunuza gönderilen kodu girin',
            hi: 'अपने मोबाइल पर भेजा गया कोड दर्ज करें',
            ur: 'آپ کے موبائل پر بھیجا گیا کوڈ درج کریں',
          ),
        ),
        const SizedBox(height: 22),
        _otpBoxes(layout),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _step = _ForgotStep.mobile;
                      _otp = '';
                      _error = null;
                    }),
            icon: const Icon(LucideIcons.pencil, size: 14),
            label: Text(_l(
              ar: 'تعديل رقم الجوال',
              en: 'Change mobile number',
              es: 'Cambiar número',
              tr: 'Numarayı değiştir',
              hi: 'मोबाइल बदलें',
              ur: 'نمبر تبدیل کریں',
            )),
            style: TextButton.styleFrom(
              foregroundColor: _kPrimary,
              textStyle: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          _errorBanner(_error!),
        ],
      ],
    );

    final pad = _numpad(layout);

    // Desktop/wide: side-by-side so the OTP preview stays visible while the
    // user taps the numpad. Mobile/tablet: stacked, numpad at the bottom.
    final body = layout == _Layout.wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: 28),
              SizedBox(width: 340, child: pad),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info,
              const SizedBox(height: 18),
              pad,
            ],
          );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          const SizedBox(height: 20),
          _primaryButton(
            label: _l(
              ar: 'تأكيد',
              en: 'Verify',
              es: 'Verificar',
              tr: 'Doğrula',
              hi: 'सत्यापित करें',
              ur: 'تصدیق کریں',
            ),
            icon: LucideIcons.check,
            onPressed: _submitCode,
          ),
        ],
      ),
    );
  }

  Widget _otpBoxes(_Layout layout) {
    return LayoutBuilder(builder: (ctx, c) {
      final maxWidth = c.maxWidth.isFinite ? c.maxWidth : 320.0;
      final double boxW = ((maxWidth - 5 * 8) / _otpLength).clamp(38.0, 56.0);
      final double boxH = boxW * 1.25;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_otpLength, (i) {
          final filled = i < _otp.length;
          final active = i == _otp.length && !_busy;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: boxW,
              height: boxH,
              decoration: BoxDecoration(
                color:
                    filled ? _kPrimary.withValues(alpha: 0.06) : _kBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: filled
                      ? _kPrimary
                      : active
                          ? _kPrimary.withValues(alpha: 0.45)
                          : _kBorder,
                  width: filled || active ? 2 : 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: filled
                  ? Container(
                      width: boxW * 0.32,
                      height: boxW * 0.32,
                      decoration: const BoxDecoration(
                        color: _kPrimary,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          );
        }),
      );
    });
  }

  // ─────────────────── Step 3: reset ───────────────────

  Widget _buildResetStep(_Layout layout) {
    return _card(
      child: Form(
        key: _resetFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              LucideIcons.key,
              _l(
                ar: 'كلمة المرور الجديدة',
                en: 'New Password',
                es: 'Nueva Contraseña',
                tr: 'Yeni Şifre',
                hi: 'नया पासवर्ड',
                ur: 'نیا پاس ورڈ',
              ),
              _l(
                ar: 'اختر كلمة مرور جديدة لحسابك',
                en: 'Choose a new password for your account',
                es: 'Elige una nueva contraseña para tu cuenta',
                tr: 'Hesabınız için yeni bir şifre seçin',
                hi: 'अपने खाते के लिए नया पासवर्ड चुनें',
                ur: 'اپنے اکاؤنٹ کے لیے نیا پاس ورڈ چنیں',
              ),
            ),
            const SizedBox(height: 22),
            _passwordField(
              controller: _passwordCtrl,
              label: _l(ar: 'كلمة المرور الجديدة', en: 'New password'),
              validator: (v) {
                final t = v ?? '';
                if (t.length < 6) {
                  return _l(
                      ar: 'كلمة المرور 6 أحرف على الأقل',
                      en: 'Password must be at least 6 characters');
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _passwordField(
              controller: _confirmCtrl,
              label: _l(ar: 'تأكيد كلمة المرور', en: 'Confirm password'),
              validator: (v) {
                if (v != _passwordCtrl.text) {
                  return _l(
                      ar: 'كلمتا المرور غير متطابقتين',
                      en: 'Passwords do not match');
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _errorBanner(_error!),
            ],
            const SizedBox(height: 20),
            _primaryButton(
              label: _l(
                ar: 'تعيين كلمة المرور',
                en: 'Set Password',
                es: 'Guardar Contraseña',
                tr: 'Şifreyi Kaydet',
                hi: 'पासवर्ड सेट करें',
                ur: 'پاس ورڈ محفوظ کریں',
              ),
              icon: LucideIcons.check,
              onPressed: _submitReset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_busy,
      obscureText: true,
      style: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 4,
        color: _kTextDark,
      ),
      decoration: _fieldDecoration(
        label: label,
        icon: LucideIcons.lock,
      ),
      validator: validator,
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: _kTextMuted),
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: const Color(0xFFCBD5E1),
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, size: 20, color: _kTextMuted),
      filled: true,
      fillColor: _kBg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kPrimary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kDanger),
      ),
    );
  }

  // ─────────────────── Done ───────────────────

  Widget _buildDoneStep() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _header(
            LucideIcons.checkCircle2,
            _l(
              ar: 'تم إعادة تعيين كلمة المرور',
              en: 'Password Reset',
              es: '¡Contraseña Restablecida!',
              tr: 'Şifre Güncellendi',
              hi: 'पासवर्ड रीसेट हो गया',
              ur: 'پاس ورڈ بحال ہوگیا',
            ),
            _l(
              ar: 'يمكنك الآن تسجيل الدخول بكلمة المرور الجديدة',
              en: 'You can now sign in with your new password',
              es: 'Ya puedes iniciar sesión con tu nueva contraseña',
              tr: 'Yeni şifrenizle giriş yapabilirsiniz',
              hi: 'अब आप नए पासवर्ड से लॉगिन कर सकते हैं',
              ur: 'اب آپ نئے پاس ورڈ سے لاگ ان ہوسکتے ہیں',
            ),
            iconColor: _kSuccess,
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: _l(
              ar: 'العودة إلى تسجيل الدخول',
              en: 'Back to Sign In',
              es: 'Volver a Iniciar Sesión',
              tr: 'Girişe Dön',
              hi: 'साइन इन पर वापस जाएँ',
              ur: 'واپس لاگ ان پر',
            ),
            icon: LucideIcons.logIn,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ─────────────────── Building blocks ───────────────────

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _header(IconData icon, String title, String subtitle,
      {Color iconColor = _kPrimary}) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: 28, color: iconColor),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: _kTextDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 13,
            color: _kTextMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, size: 16, color: _kDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: const Color(0xFFB91C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _kPrimary.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ─────────────────── Numpad ───────────────────

  Widget _numpad(_Layout layout) {
    return LayoutBuilder(builder: (ctx, c) {
      final maxW = c.maxWidth.isFinite ? c.maxWidth : 320.0;
      const gap = 10.0;
      // Three columns, comfortable tap targets on every device (Sunmi/phone
      // 52-72, tablets 72-92, desktop capped at 88).
      double btn = (maxW - gap * 2) / 3;
      if (layout == _Layout.compact) {
        btn = btn.clamp(56.0, 78.0);
      } else if (layout == _Layout.medium) {
        btn = btn.clamp(68.0, 92.0);
      } else {
        btn = btn.clamp(64.0, 88.0);
      }
      final padW = btn * 3 + gap * 2;
      return Center(
        child: SizedBox(
          width: padW,
          child: Column(
            children: [
              _padRow(const ['1', '2', '3'], btn, gap),
              SizedBox(height: gap),
              _padRow(const ['4', '5', '6'], btn, gap),
              SizedBox(height: gap),
              _padRow(const ['7', '8', '9'], btn, gap),
              SizedBox(height: gap),
              Row(
                children: [
                  _padAction(
                    icon: LucideIcons.eraser,
                    onTap: _onPadClear,
                    size: btn,
                  ),
                  SizedBox(width: gap),
                  _padDigit('0', btn),
                  SizedBox(width: gap),
                  _padAction(
                    icon: LucideIcons.delete,
                    onTap: _onPadBackspace,
                    size: btn,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _padRow(List<String> digits, double size, double gap) {
    return Row(
      children: [
        _padDigit(digits[0], size),
        SizedBox(width: gap),
        _padDigit(digits[1], size),
        SizedBox(width: gap),
        _padDigit(digits[2], size),
      ],
    );
  }

  Widget _padDigit(String d, double size) {
    return _NumpadButton(
      size: size,
      onTap: () => _onPadDigit(d),
      child: Text(
        d,
        style: GoogleFonts.inter(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: _kTextDark,
        ),
      ),
    );
  }

  Widget _padAction({
    required IconData icon,
    required VoidCallback onTap,
    required double size,
  }) {
    return _NumpadButton(
      size: size,
      onTap: onTap,
      tinted: true,
      child: Icon(icon, color: _kPrimary, size: size * 0.32),
    );
  }
}

class _NumpadButton extends StatefulWidget {
  final double size;
  final VoidCallback onTap;
  final Widget child;
  final bool tinted;

  const _NumpadButton({
    required this.size,
    required this.onTap,
    required this.child,
    this.tinted = false,
  });

  @override
  State<_NumpadButton> createState() => _NumpadButtonState();
}

class _NumpadButtonState extends State<_NumpadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFFF7F8FB);
    final tintedBase = const Color(0xFFFFF3E6);
    final pressed = widget.tinted
        ? const Color(0xFFFFE2C2)
        : const Color(0xFFE6E8EF);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _pressed
              ? pressed
              : widget.tinted
                  ? tintedBase
                  : baseColor,
          borderRadius: BorderRadius.circular(widget.size * 0.24),
          border: Border.all(
            color: widget.tinted
                ? const Color(0xFFFFD6A8)
                : const Color(0xFFE6E8EF),
          ),
        ),
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}
