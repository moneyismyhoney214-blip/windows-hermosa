import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../services/api/auth_service.dart';
import '../services/language_service.dart';

/// Three-step password-reset flow: request code → verify code → set new
/// password. Each step has its own form so errors surface right next to
/// the input that caused them, and Back keeps previous input alive while
/// the cashier iterates.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _ForgotStep { email, code, reset, done }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _auth = getIt<AuthService>();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  _ForgotStep _step = _ForgotStep.email;
  bool _busy = false;
  String? _error;

  // Carried between step 1 (send code) and step 2 (check code).
  String? _expires;
  String? _signature;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLangChanged);
  }

  @override
  void dispose() {
    translationService.removeListener(_onLangChanged);
    _emailCtrl.dispose();
    _codeCtrl.dispose();
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

  Future<void> _submitEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await _auth.sendForgotPasswordCode(_emailCtrl.text);
      // Accept either flat `{expires, signature}` or nested `{data: {...}}`.
      dynamic data = response['data'] is Map
          ? (response['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : response;
      if (data is! Map) data = response;
      _expires = (data['expires'] ?? data['expires_at'])?.toString();
      _signature = data['signature']?.toString();
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
    if (!_codeFormKey.currentState!.validate()) return;
    final expires = _expires;
    final signature = _signature;
    if (expires == null || signature == null) {
      setState(() => _error = _l(
            ar: 'انتهت الجلسة، أعد إرسال الكود',
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
      await _auth.checkResetCode(
        email: _emailCtrl.text.trim(),
        expires: expires,
        signature: signature,
        code: _codeCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _step = _ForgotStep.reset;
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

  Future<void> _submitReset() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.resetForgottenPassword(_passwordCtrl.text);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(
          _tr('forgot_password'),
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _buildCurrentStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case _ForgotStep.email:
        return _buildEmailStep();
      case _ForgotStep.code:
        return _buildCodeStep();
      case _ForgotStep.reset:
        return _buildResetStep();
      case _ForgotStep.done:
        return _buildDoneStep();
    }
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(LucideIcons.mail, _l(
            ar: 'استعادة كلمة المرور',
            en: 'Recover Password',
            es: 'Recuperar Contraseña',
            tr: 'Şifre Kurtarma',
            hi: 'पासवर्ड रिकवर',
            ur: 'پاس ورڈ بحالی',
          ), _l(
            ar: 'أدخل بريدك الإلكتروني لإرسال كود استعادة كلمة المرور',
            en: 'Enter your email to receive a reset code',
            es: 'Ingresa tu email para recibir un código de recuperación',
            tr: 'E-posta adresinizi girin; sıfırlama kodu göndereceğiz',
            hi: 'रीसेट कोड प्राप्त करने के लिए अपना ईमेल दर्ज करें',
            ur: 'ری سیٹ کوڈ حاصل کرنے کیلئے اپنا ای میل درج کریں',
          )),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            enabled: !_busy,
            decoration: _inputDecoration(
              _tr('email'),
              LucideIcons.mail,
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) {
                return _l(ar: 'البريد الإلكتروني مطلوب', en: 'Email required');
              }
              if (!t.contains('@') || !t.contains('.')) {
                return _l(ar: 'بريد إلكتروني غير صحيح', en: 'Invalid email');
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          if (_error != null) _errorBanner(_error!),
          const SizedBox(height: 8),
          _primaryButton(
            label: _l(
              ar: 'إرسال كود الاستعادة',
              en: 'Send Reset Code',
              es: 'Enviar Código',
              tr: 'Kodu Gönder',
              hi: 'कोड भेजें',
              ur: 'کوڈ بھیجیں',
            ),
            onPressed: _submitEmail,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeStep() {
    return Form(
      key: _codeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(LucideIcons.shield, _l(
            ar: 'تأكيد الكود',
            en: 'Verify Code',
            es: 'Verificar Código',
            tr: 'Kodu Doğrula',
            hi: 'कोड सत्यापित करें',
            ur: 'کوڈ کی تصدیق',
          ), _l(
            ar: 'أدخل الكود المرسل إلى بريدك',
            en: 'Enter the code sent to your email',
            es: 'Ingresa el código enviado a tu correo',
            tr: 'E-postanıza gönderilen kodu girin',
            hi: 'अपने ईमेल पर भेजा गया कोड दर्ज करें',
            ur: 'آپ کے ای میل پر بھیجا گیا کوڈ درج کریں',
          )),
          const SizedBox(height: 24),
          TextFormField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            enabled: !_busy,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
            decoration: _inputDecoration(
              '------',
              LucideIcons.hash,
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) {
                return _l(ar: 'الكود مطلوب', en: 'Code required');
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          if (_error != null) _errorBanner(_error!),
          const SizedBox(height: 8),
          _primaryButton(
            label: _l(
              ar: 'تأكيد',
              en: 'Verify',
              es: 'Verificar',
              tr: 'Doğrula',
              hi: 'सत्यापित करें',
              ur: 'تصدیق کریں',
            ),
            onPressed: _submitCode,
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _step = _ForgotStep.email;
                      _error = null;
                    }),
            child: Text(_l(
              ar: 'رجوع',
              en: 'Back',
              es: 'Atrás',
              tr: 'Geri',
              hi: 'वापस',
              ur: 'پیچھے',
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildResetStep() {
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(LucideIcons.key, _l(
            ar: 'كلمة المرور الجديدة',
            en: 'New Password',
            es: 'Nueva Contraseña',
            tr: 'Yeni Şifre',
            hi: 'नया पासवर्ड',
            ur: 'نیا پاس ورڈ',
          ), _l(
            ar: 'أدخل كلمة المرور الجديدة التي تريد استخدامها',
            en: 'Choose a new password for your account',
            es: 'Elige una nueva contraseña para tu cuenta',
            tr: 'Hesabınız için yeni bir şifre seçin',
            hi: 'अपने खाते के लिए नया पासवर्ड चुनें',
            ur: 'اپنے اکاؤنٹ کے لیے نیا پاس ورڈ چنیں',
          )),
          const SizedBox(height: 24),
          TextFormField(
            controller: _passwordCtrl,
            enabled: !_busy,
            obscureText: true,
            decoration: _inputDecoration(
              _l(ar: 'كلمة المرور الجديدة', en: 'New password'),
              LucideIcons.lock,
            ),
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
          TextFormField(
            controller: _confirmCtrl,
            enabled: !_busy,
            obscureText: true,
            decoration: _inputDecoration(
              _l(ar: 'تأكيد كلمة المرور', en: 'Confirm password'),
              LucideIcons.lock,
            ),
            validator: (v) {
              if (v != _passwordCtrl.text) {
                return _l(
                    ar: 'كلمتا المرور غير متطابقتين',
                    en: 'Passwords do not match');
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          if (_error != null) _errorBanner(_error!),
          const SizedBox(height: 8),
          _primaryButton(
            label: _l(
              ar: 'تعيين كلمة المرور',
              en: 'Set Password',
              es: 'Guardar Contraseña',
              tr: 'Şifreyi Kaydet',
              hi: 'पासवर्ड सेट करें',
              ur: 'پاس ورڈ محفوظ کریں',
            ),
            onPressed: _submitReset,
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          iconColor: const Color(0xFF16A34A),
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
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _header(IconData icon, String title, String subtitle,
      {Color iconColor = const Color(0xFFF58220)}) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 36, color: iconColor),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
              fontSize: 14, color: const Color(0xFF64748B), height: 1.4),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFF58220), width: 2),
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle,
              size: 18, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: const Color(0xFFB91C1C),
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF58220),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            : Text(
                label,
                style: GoogleFonts.cairo(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
