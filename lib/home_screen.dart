import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/features/buys/buys_screen.dart';
import 'package:tatweer/features/collections/collections_screen.dart';
import 'package:tatweer/features/coding/coding_screen.dart';
import 'package:tatweer/features/exchange/exchange_screen.dart';
import 'package:tatweer/services/local_db_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';
import 'widgets/shared/connection_status.dart';
import 'login_screen.dart';
import 'features/sells/sells_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool internetAvailable;
  const HomeScreen({super.key, required this.internetAvailable});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocalDbService _localDb = LocalDbService.instance;

  String _userName = '';
  int _roleId = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'مستخدم';
      _roleId = prefs.getInt('role_id') ?? 0;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _localDb.clearAllTables();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LoginScreen(internetAvailable: widget.internetAvailable),
      ),
    );
  }

  void _navigateToSells() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SellsScreen(internetAvailable: widget.internetAvailable),
    ),
  );

  void _navigateToBuys() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BuysScreen(internetAvailable: widget.internetAvailable),
    ),
  );

  void _navigateToCollections() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          CollectionsScreen(internetAvailable: widget.internetAvailable),
    ),
  );

  void _navigateToCoding() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const CodingScreen()),
  );

  void _navigateToExchange() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          ExchangeScreen(internetAvailable: widget.internetAvailable),
    ),
  );

  // ================= UI =================

  Widget _buildWelcomeCard() {
    final w = MediaQuery.of(context).size.width;

    return FadeInDown(
      duration: const Duration(milliseconds: 700),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(w * 0.05),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.15),
              AppColors.primary.withOpacity(0.05),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.16,
              height: w * 0.16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
              child: Icon(Icons.person, color: Colors.white, size: w * 0.08),
            ),
            SizedBox(width: w * 0.04),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مرحباً, $_userName 👋',
                    style: AppStyles.heading2(context).copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConnectionStatus(internetAvailable: widget.internetAvailable),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionList() {
    return Column(
      children: [
        FadeInUp(
          duration: const Duration(milliseconds: 600),
          child: Text(
            'العمليات الرئيسية',
            style: AppStyles.heading2(
              context,
            ).copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            children: [
              _animatedCard(
                0,
                'بيع',
                Icons.shopping_cart_checkout_rounded,
                AppColors.sells,
                LinearGradient(colors: [AppColors.sells, AppColors.sellsDark]),
                _navigateToSells,
              ),

              _animatedCard(
                1,
                'تحصيل',
                Icons.payments_rounded,
                AppColors.success,
                LinearGradient(
                  colors: [AppColors.success, AppColors.collectionsDark],
                ),
                _navigateToCollections,
              ),

              _animatedCard(
                2,
                'تكويد',
                Icons.qr_code_2_rounded,
                AppColors.coding,
                LinearGradient(
                  colors: [AppColors.coding, AppColors.codingDark],
                ),
                _navigateToCoding,
              ),

              if (_roleId == 1) ...[
                _animatedCard(
                  3,
                  'شراء',
                  Icons.shopping_bag_rounded,
                  AppColors.buys,
                  LinearGradient(colors: [AppColors.buys, AppColors.buysDark]),
                  _navigateToBuys,
                ),

                _animatedCard(
                  4,
                  'تحويل منتجات',
                  Icons.swap_horiz_rounded,
                  AppColors.exchange,
                  LinearGradient(
                    colors: [AppColors.exchange, AppColors.exchangeDark],
                  ),
                  _navigateToExchange,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _animatedCard(
    int index,
    String title,
    IconData icon,
    Color color,
    Gradient gradient,
    VoidCallback onTap,
  ) {
    return FadeInUp(
      delay: Duration(milliseconds: 200 * index),
      duration: const Duration(milliseconds: 700),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: _buildEnhancedActionCard(
          title: title,
          icon: icon,
          color: color,
          gradient: gradient,
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildEnhancedActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    final w = MediaQuery.of(context).size.width;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: w * 0.32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: gradient,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -10,
              child: Icon(
                icon,
                size: w * 0.3,
                color: Colors.white.withOpacity(0.07),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: w * 0.15,
                    height: w * 0.15,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    child: Icon(icon, size: w * 0.08, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: AppStyles.heading2(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= MAIN =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.primary,
        centerTitle: true,
        title: Text(
          'الصفحة الرئيسية',
          style: AppStyles.heading2(
            context,
          ).copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          FadeInRight(
            child: IconButton(
              onPressed: _logout,
              icon: const Icon(
                Icons.logout_rounded,
                color: AppColors.background,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildWelcomeCard(),
              const SizedBox(height: 15),
              Expanded(child: _buildActionList()),
            ],
          ),
        ),
      ),
    );
  }
}
