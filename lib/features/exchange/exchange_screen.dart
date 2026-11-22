import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/features/exchange/exchange_bill_details_screen.dart';
import 'package:tatweer/features/exchange/new_exchange_bill_screen.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';
import '../../../widgets/shared/action_button.dart';
import '../../../widgets/shared/tab_content_builder.dart';

class ExchangeScreen extends StatefulWidget {
  final bool internetAvailable;
  const ExchangeScreen({super.key, required this.internetAvailable});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  final SyncService _syncService = SyncService.instance;
  final LocalDbService _localDb = LocalDbService.instance;

  List<Map<String, dynamic>> _syncedBills = [];
  List<Map<String, dynamic>> _unsyncedBills = [];
  bool _loading = false;
  bool _syncing = false;
  bool _refreshing = false;
  String _error = '';
  String _statusSynced = '';
  String _statusUnsynced = '';

  @override
  void initState() {
    super.initState();
    _loadExchangeBills();
  }

  Future<void> _loadExchangeBills() async {
    setState(() {
      _loading = true;
      _error = '';
      _statusSynced = 'جاري تحميل الفواتير المتزامنة...';
      _statusUnsynced = 'جاري تحميل الفواتير غير المتزامنة...';
    });

    try {
      await _loadSyncedExchangeBills();
      await _loadUnsyncedExchangeBills();
    } catch (e) {
      setState(() => _error = 'حدث خطأ عند تحميل البيانات: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _syncUserData() async {
    if (_refreshing) return;

    setState(() => _refreshing = true);

    try {
      if (!widget.internetAvailable) {
        showSnackBar(
          context,
          'فشل تحديث البيانات يرجى التأكد من الاتصال بالانترنت',
          isError: true,
        );

        if (mounted) {
          setState(() => _refreshing = false);
        }
        return;
      }

      await _syncService.syncUserData();
      showSnackBar(
        context,
        'تم تحديث بيانات الموردين والمنتجات من الخادم',
        isError: false,
      );
    } catch (e) {
      print('Error syncing user data: $e');
      showSnackBar(
        context,
        'فشل تحديث البيانات يرجى المحاولة لاحقا',
        isError: true,
      );
    } finally {
      if (mounted && _refreshing) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _loadSyncedExchangeBills() async {
    try {
      List<Map<String, dynamic>> bills = [];
      bool fromServer = false;

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId != null) {
        if (widget.internetAvailable) {
          final result = await _syncService.fetchUserExchangeBills();
          fromServer = result['fromServer'];

          if (fromServer) {
            showSnackBar(
              context,
              '🌐 تم تحميل الفواتير من الخادم',
              isError: false,
            );
            setState(() => _statusSynced = 'تم تحميل الفواتير من الخادم');
          } else {
            showSnackBar(
              context,
              '📦 تعذر الاتصال، جاري التحميل من التخزين المحلي',
              isError: false,
            );
            setState(() => _statusSynced = 'تم التحميل من التخزين المحلي');
          }
        } else {
          showSnackBar(
            context,
            '📦 تم التحميل من التخزين المحلي',
            isError: false,
          );
          setState(() => _statusSynced = 'تم التحميل من التخزين المحلي');
        }

        bills = await _localDb.getUserExchangeBills(userId);
      }

      bills = bills.where((bill) {
        final synced = bill['Synced'] == 1 || bill['Synced'] == true;
        final hasValidData = bill['Id'] != null;
        return synced && hasValidData;
      }).toList();

      final enhanced = await _enhanceBillsWithBranchNames(bills);
      setState(() => _syncedBills = enhanced);
    } catch (e) {
      print('Error in _loadSyncedExchangeBills: $e');
      setState(() {
        _syncedBills = [];
        _statusSynced = 'خطأ عند تحميل الفواتير المتزامنة';
      });
    }
  }

  Future<void> _loadUnsyncedExchangeBills() async {
    try {
      final pending = await _localDb.getPendingExchangeBills();
      final validPending = pending.where((bill) {
        return bill['Id'] != null;
      }).toList();

      final enhanced = await _enhanceBillsWithBranchNames(validPending);
      setState(() => _unsyncedBills = enhanced);

      setState(
        () => _statusUnsynced = enhanced.isEmpty
            ? 'لا توجد فواتير غير متزامنة'
            : '${enhanced.length} فاتورة غير متزامنة',
      );
    } catch (e) {
      print('Error in _loadUnsyncedExchangeBills: $e');
      setState(() {
        _unsyncedBills = [];
        _statusUnsynced = 'خطأ عند تحميل الفواتير غير المتزامنة';
      });
    }
  }

  Future<void> _syncAllPendingExchangeBills() async {
    setState(() => _syncing = true);

    try {
      await _syncService.syncPendingExchangeToServer();
      await _loadExchangeBills();
      showSnackBar(context, 'تمت مزامنة جميع الفواتير بنجاح', isError: false);
    } catch (e) {
      showSnackBar(
        context,
        'تعذر الاتصال بالخادم. تأكد من اتصالك بالإنترنت وحاول مرة أخرى.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Enhance bills by adding branch names for BranchId and DestBranchId
  Future<List<Map<String, dynamic>>> _enhanceBillsWithBranchNames(
    List<Map<String, dynamic>> bills,
  ) async {
    final enhanced = <Map<String, dynamic>>[];
    for (final bill in bills) {
      try {
        final fromBranchId = bill['BranchId'];
        final toBranchId = bill['DestBranchId'];

        String fromBranchName = 'غير معروف';
        String toBranchName = 'غير معروف';

        if (fromBranchId != null) {
          final branch = await _localDb.getBranchById(fromBranchId);
          fromBranchName = branch != null
              ? branch['Name']?.toString() ?? 'غير معروف'
              : 'غير معروف';
        }
        if (toBranchId != null) {
          final branch = await _localDb.getBranchById(toBranchId);
          toBranchName = branch != null
              ? branch['Name']?.toString() ?? 'غير معروف'
              : 'غير معروف';
        }

        enhanced.add({
          ...bill,
          'FromBranchName': fromBranchName,
          'ToBranchName': toBranchName,
          'BillNumber': bill['Bill'] ?? 'محلية',
          'Total': bill['Total'] ?? 0.0,
          'Date': bill['TheDate'] ?? '-',
        });
      } catch (_) {
        enhanced.add({
          ...bill,
          'FromBranchName': 'غير معروف',
          'ToBranchName': 'غير معروف',
          'BillNumber': bill['Bill'] ?? 'محلية',
          'Total': bill['Total'] ?? 0.0,
          'Date': bill['TheDate'] ?? '-',
        });
      }
    }
    return enhanced;
  }

  Widget _buildBillItem(Map<String, dynamic> bill, bool isSynced) {
    final billNumber = bill['BillNumber'] ?? 'محلية';
    final total = bill['Total'] ?? 0;
    final date = bill['Date'] ?? '-';
    final fromBranch = bill['FromBranchName'] ?? 'غير معروف';
    final toBranch = bill['ToBranchName'] ?? 'غير معروف';
    final isLocked = bill['Lock'] == 'Lock';

    return FadeInUp(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
          border: Border.all(
            color: isSynced
                ? AppColors.success.withOpacity(0.3)
                : AppColors.warning.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSynced
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.warning.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSynced ? AppColors.success : AppColors.warning,
                width: 1.5,
              ),
            ),
            child: Icon(
              isSynced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: isSynced ? AppColors.success : AppColors.warning,
              size: 20,
            ),
          ),
          title: Text(
            'فاتورة تحويل #$billNumber',
            style: AppStyles.bodyMedium(context).copyWith(
              fontWeight: FontWeight.bold,
              color: isSynced ? AppColors.success : AppColors.warning,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'التاريخ: $date',
                style: AppStyles.bodySmall(context),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'من فرع: $fromBranch',
                style: AppStyles.bodySmall(context),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'إلى فرع: $toBranch',
                style: AppStyles.bodySmall(context),
                overflow: TextOverflow.ellipsis,
              ),
              if (isLocked)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'مغلقة',
                    style: AppStyles.bodySmall(context).copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!isSynced && !isLocked)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '⏳ في انتظار المزامنة',
                    style: AppStyles.bodySmall(context).copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          trailing: SizedBox(
            width: 80,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$total ج.م',
                  style: AppStyles.bodyMedium(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: isSynced ? AppColors.success : AppColors.warning,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isSynced && !isLocked)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'غير متزامن',
                      style: AppStyles.bodySmall(
                        context,
                      ).copyWith(color: AppColors.warning),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExchangeBillDetailsScreen(
                  bill: bill,
                  internetAvailable: widget.internetAvailable,
                ),
              ),
            );
            if (result == true) {
              _loadExchangeBills();
            }
          },
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'التحويلات',
          style: AppStyles.heading2(
            context,
          ).copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        centerTitle: true,
        elevation: 0,
        actions: [
          ActionButton(
            icon: Icons.sync_rounded,
            label: 'مزامنة',
            onPressed: _syncAllPendingExchangeBills,
            isLoading: _syncing,
            backgroundColor: _syncing ? AppColors.secondary : AppColors.success,
          ),
          ActionButton(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _syncUserData,
            isLoading: _refreshing,
            backgroundColor: _refreshing
                ? AppColors.secondary
                : AppColors.primary.withAlpha(2),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withOpacity(0.05),
              AppColors.primary.withOpacity(0.02),
              Colors.transparent,
            ],
          ),
        ),
        child: _loading
            ? _buildLoading()
            : _error.isNotEmpty
            ? _buildError()
            : _buildTabs(),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () async {
            final created = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NewExchangeBillScreen()),
            );
            if (created == true) _loadExchangeBills();
          },
          icon: Icon(Icons.add_rounded, size: AppStyles.iconSize(context)),
          label: Text(
            'فاتورة تحويل جديدة',
            style: AppStyles.bodyMedium(
              context,
            ).copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              labelColor: AppColors.onPrimary,
              unselectedLabelColor: AppColors.tabUnselected,
              labelStyle: AppStyles.bodyMedium(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
              unselectedLabelStyle: AppStyles.bodyMedium(context),
              tabs: const [
                Tab(text: 'فواتير متزامنة'),
                Tab(text: 'فواتير غير متزامنة'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTabContent(_syncedBills, _statusSynced, true),
                _buildTabContent(_unsyncedBills, _statusUnsynced, false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(
    List<Map<String, dynamic>> bills,
    String status,
    bool isSynced,
  ) {
    return TabContentBuilder(
      items: bills,
      status: status,
      isSynced: isSynced,
      emptyIcon: isSynced
          ? Icons.cloud_done_rounded
          : Icons.sync_problem_rounded,
      emptyMessage: isSynced
          ? 'لا توجد فواتير متزامنة'
          : 'لا توجد فواتير غير متزامنة',
      statusMessage: isSynced
          ? '${bills.length} فاتورة متزامنة مع الخادم'
          : '${bills.length} فاتورة في انتظار المزامنة',
      itemBuilder: (context, bill, isSynced) => _buildBillItem(bill, isSynced),
    );
  }

  Widget _buildLoading() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'جاري تحميل الفواتير...',
          style: AppStyles.heading2(context).copyWith(color: AppColors.primary),
        ),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 80),
          const SizedBox(height: 20),
          Text(
            _error,
            style: AppStyles.heading2(context).copyWith(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'حدث خطأ أثناء تحميل البيانات',
            style: AppStyles.bodyMedium(
              context,
            ).copyWith(color: AppColors.secondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ActionButton(
            icon: Icons.refresh_rounded,
            label: 'إعادة المحاولة',
            onPressed: _loadExchangeBills,
            isLoading: false,
            backgroundColor: AppColors.primary,
          ),
        ],
      ),
    ),
  );
}
