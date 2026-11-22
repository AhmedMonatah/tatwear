import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/utils/app_colors.dart';
import 'package:tatweer/utils/app_styles.dart';
import 'add_new_client_screen.dart';
import 'add_new_seller_screen.dart';
import 'add_new_item_screen.dart';

class CodingScreen extends StatefulWidget {
  const CodingScreen({super.key});

  @override
  State<CodingScreen> createState() => _CodingScreenState();
}

class _CodingScreenState extends State<CodingScreen> {
  int? roleId;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      roleId = prefs.getInt('role_id') ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (roleId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'تكويد',
          style: AppStyles.heading2(
            context,
          ).copyWith(color: AppColors.onPrimary),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.background, AppColors.surfaceVariant],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: AppStyles.screenPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // show only client option if role_id != 1
              if (roleId != 1) ...[
                _buildCodingOption(
                  context,
                  title: 'إضافة عميل جديد',
                  icon: Icons.person_add,
                  color: AppColors.codingDark,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddNewClientScreen(),
                    ),
                  ),
                ),
              ] else ...[
                _buildCodingOption(
                  context,
                  title: 'إضافة عميل جديد',
                  icon: Icons.person_add,
                  color: AppColors.codingDark,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddNewClientScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildCodingOption(
                  context,
                  title: 'إضافة مورد جديد',
                  icon: Icons.business,
                  color: AppColors.purchases,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddNewSellerScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildCodingOption(
                  context,
                  title: 'إضافة صنف جديد',
                  icon: Icons.add_box,
                  color: AppColors.success,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddNewItemScreen()),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodingOption(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: FadeInLeft(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: AppStyles.iconSize(context) * 1.5,
                color: AppColors.onPrimary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: AppStyles.heading2(context).copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: AppColors.onPrimary,
                size: AppStyles.iconSize(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
