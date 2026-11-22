import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';
import '../utils/constants.dart';
import 'widgets/shared/connection_status.dart';
import 'services/remote_db_service.dart';
import 'services/sync_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool internetAvailable;
  const LoginScreen({super.key, required this.internetAvailable});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final RemoteDbService _remoteDb = RemoteDbService.instance;
  final SyncService _syncService = SyncService.instance;

  bool _loading = false;
  String? _message;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    final id = _idCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (id.isEmpty || pass.isEmpty) {
      setState(() {
        _loading = false;
        _message = 'يرجى إدخال رقم المستخدم او الاسم وكلمة المرور.';
      });
      return;
    }

    final isDemoUser = id == DB_USER && pass == DB_PASS;

    // MODIFICATION: Require internet for login
    if (!widget.internetAvailable && !isDemoUser) {
      setState(() {
        _loading = false;
        _message = 'يجب توفر اتصال بالإنترنت لتسجيل الدخول.';
      });
      return;
    }

    try {
      Map<String, dynamic>? user;

      // Only remote login allowed
      user = await _remoteLogin(id, pass);

      if (user != null) {
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                HomeScreen(internetAvailable: widget.internetAvailable),
          ),
        );
      } else {
        setState(() {
          _message =
              'بيانات الدخول غير صحيحة. تأكد من رقم المستخدم او الاسم وكلمة المرور.';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'حدث خطأ أثناء عملية الدخول: ${e.toString()}';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _remoteLogin(String id, String pass) async {
    try {
      final user = await _remoteDb.authenticateUser(id, pass);
      if (user != null) {
        await _saveUserData(user);
        await _syncService.syncUserData();
        return user;
      }
      return null;
    } catch (e) {
      print('Remote login failed: $e');
      return null;
    }
  }

  Future<void> _saveUserData(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', user['Id']);
    await prefs.setString('user_name', user['Name'] ?? '');
    await prefs.setInt('branch_id', user['BranchId'] ?? 0);
    await prefs.setInt('role_id', user['RoleId'] ?? 0);
    await prefs.setBool('is_online_login', widget.internetAvailable);
  }

  Widget _buildMessage() {
    if (_message == null) return const SizedBox.shrink();

    final isError =
        _message!.contains('غير صحيحة') ||
        _message!.contains('خطأ') ||
        _message!.contains('يرجى') ||
        _message!.contains('يجب توفر اتصال');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.error.withOpacity(0.1)
            : AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isError ? AppColors.error : AppColors.success,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? AppColors.error : AppColors.success,
            size: AppStyles.iconSize(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _message!,
              style: AppStyles.bodyMedium(context).copyWith(
                color: isError ? AppColors.error : AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Advisor',
          style: AppStyles.heading2(
            context,
          ).copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        centerTitle: true,
        elevation: 0,
      ),

      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
          child: Column(
            children: [
              SizedBox(
                width: screenWidth * 0.35,
                height: screenHeight * 0.12,
                child: Image.asset(
                  "assets/images/logo.png",
                  fit: BoxFit.contain,
                ),
              ),

              Text(
                'تسجيل الدخول',
                style: AppStyles.heading1(context).copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),

              Text(
                'مرحباً بعودتك',
                style: AppStyles.bodyMedium(
                  context,
                ).copyWith(color: AppColors.secondary),
              ),

              SizedBox(height: screenHeight * 0.03),
              ConnectionStatus(internetAvailable: widget.internetAvailable),
              SizedBox(height: screenHeight * 0.03),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    TextField(
                      controller: _idCtrl,
                      decoration: AppStyles.textFieldDecoration(
                        'رقم المستخدم او الاسم',
                        context,
                      ).copyWith(prefixIcon: const Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: AppStyles.textFieldDecoration(
                        'كلمة المرور',
                        context,
                      ).copyWith(prefixIcon: const Icon(Icons.lock_outline)),
                    ),

                    const SizedBox(height: 20),
                    _buildMessage(),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: screenHeight * 0.065,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 5,
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(
                                'دخول',
                                style: AppStyles.bodyLarge(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: screenHeight * 0.035),

              //  info message for internet-only login
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.primary,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'يجب توفر اتصال بالإنترنت لتسجيل الدخول',
                        style: AppStyles.bodySmall(
                          context,
                        ).copyWith(color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
