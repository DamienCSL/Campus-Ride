import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'error_handler.dart';
import 'reset_password.dart';

class VerifyResetCodePage extends StatefulWidget {
  final String email;

  const VerifyResetCodePage({Key? key, required this.email}) : super(key: key);

  @override
  State<VerifyResetCodePage> createState() => _VerifyResetCodePageState();
}

class _VerifyResetCodePageState extends State<VerifyResetCodePage> {
  final TextEditingController codeCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _verifyCode() async {
    final code = codeCtrl.text.trim();
    if (code.isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Please enter the code from the email');
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint('🔐 [VerifyCode] Verifying recovery code for ${widget.email}...');
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: OtpType.recovery,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw AppException(
            message: 'Verification timeout. Please try again.',
            code: 'verify_timeout',
          );
        },
      );

      if (res.user != null) {
        debugPrint('✅ [VerifyCode] Code verified successfully');
        if (!mounted) return;

        // Navigate to password reset page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const ResetPasswordPage(),
          ),
        );
      } else {
        if (!mounted) return;
        ErrorHandler.showErrorSnackBar(context, 'Invalid code. Please check the email and try again.');
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      debugPrint('❌ [VerifyCode] Verify auth error: ${e.message}');
      ErrorHandler.logError('verify_code', e);
      ErrorHandler.showErrorSnackBar(context, e);
    } catch (e) {
      if (!mounted) return;
      debugPrint('❌ [VerifyCode] Verify error: $e');
      ErrorHandler.logError('verify_code', e);
      ErrorHandler.showErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: campusGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text(
                  "Verify Recovery Code",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  "Enter the recovery code sent to ${widget.email}",
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),

                // Code input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.numbers, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: codeCtrl,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Recovery code',
                            hintStyle: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Verify button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: campusGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _verifyCode,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Verify Code',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: Text(
                    'Copy the recovery code from the email you received.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }
}
