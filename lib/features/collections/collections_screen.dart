import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/widgets/shared/custom_app_bar.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';
import '../../../widgets/shared/action_button.dart';
import '../../../widgets/shared/tab_content_builder.dart';
import 'collection_details_screen.dart';
import 'new_collection_screen.dart';

class CollectionsScreen extends StatefulWidget {
  final bool internetAvailable;
  const CollectionsScreen({super.key, required this.internetAvailable});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  final SyncService _syncService = SyncService.instance;
  final LocalDbService _localDb = LocalDbService.instance;

  List<Map<String, dynamic>> _syncedCollections = [];
  List<Map<String, dynamic>> _unsyncedCollections = [];
  bool _loading = false;
  bool _syncing = false;
  bool _refreshing = false; // NEW: Added for refresh button loading state
  String _error = '';
  String _statusSynced = '';
  String _statusUnsynced = '';

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    setState(() {
      _loading = true;
      _error = '';
      _statusSynced = 'جاري تحميل فواتير التحصيل المتزامنة...';
      _statusUnsynced = 'جاري تحميل فواتير التحصيل غير المتزامنة...';
    });

    try {
      await _loadSyncedCollections();
      await _loadUnsyncedCollections();
    } catch (e) {
      setState(() => _error = 'حدث خطأ عند تحميل البيانات: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  // NEW: Refresh function with proper internet check
  Future<void> _syncUserData() async {
    if (_refreshing) return;

    setState(() => _refreshing = true);

    try {
      // Check internet availability first
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
      if (!mounted) return;
      showSnackBar(
        context,
        'تم تحديث بيانات العملاء و المنتجات من الخادم',
        isError: false,
      );
    } catch (e) {
      debugPrint('Error syncing user data: $e');
      if (!mounted) return;
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

  Future<void> _loadSyncedCollections() async {
    try {
      List<Map<String, dynamic>> collections = [];
      bool fromServer = false;

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId != null) {
        if (widget.internetAvailable) {
          // Try to sync and fetch from server
          final result = await _syncService.fetchUserCollections();
          fromServer = result['fromServer'];

          if (fromServer) {
            showSnackBar(
              context,
              '🌐 تم تحميل فواتير التحصيل من الخادم',
              isError: false,
            );
            setState(() => _statusSynced = 'تم تحميل فواتير التحصيل من الخادم');
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

        collections = await _localDb.getUserCollections(userId);
      }

      // Filter only synced collections and ensure they have valid data
      collections = collections.where((collection) {
        final synced =
            collection['Synced'] == 1 || collection['Synced'] == true;
        final hasValidData = collection['Id'] != null;
        return synced && hasValidData;
      }).toList();

      final enhanced = await _enhanceCollectionsWithClientNames(collections);
      setState(() => _syncedCollections = enhanced);
    } catch (e) {
      print('Error in _loadSyncedCollections: $e');
      setState(() {
        _syncedCollections = [];
        _statusSynced = 'خطأ عند تحميل فواتير التحصيل المتزامنة';
      });
    }
  }

  Future<void> _loadUnsyncedCollections() async {
    try {
      final pending = await _localDb.getPendingCollections();
      // Filter only valid pending collections
      final validPending = pending.where((collection) {
        return collection['Id'] != null;
      }).toList();

      final enhanced = await _enhanceCollectionsWithClientNames(validPending);
      setState(() => _unsyncedCollections = enhanced);

      setState(
        () => _statusUnsynced = enhanced.isEmpty
            ? 'لا توجد فواتير تحصيل غير متزامنة'
            : '${enhanced.length} فاتورة تحصيل غير متزامن',
      );
    } catch (e) {
      print('Error in _loadUnsyncedCollections: $e');
      setState(() {
        _unsyncedCollections = [];
        _statusUnsynced = 'خطأ عند تحميل فواتير التحصيل غير المتزامنة';
      });
    }
  }

  Future<void> _syncAllPendingCollections() async {
    setState(() => _syncing = true);

    try {
      await _syncService.syncPendingCollectionsToServer();
      await _loadCollections();
      showSnackBar(
        context,
        'تمت مزامنة جميع فواتير التحصيل بنجاح',
        isError: false,
      );
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

  Future<List<Map<String, dynamic>>> _enhanceCollectionsWithClientNames(
    List<Map<String, dynamic>> collections,
  ) async {
    final enhanced = <Map<String, dynamic>>[];
    for (final collection in collections) {
      try {
        final clientId = collection['ClientId'];
        String clientName = 'غير معروف';
        if (clientId != null) {
          final name = await _localDb.getClientName(clientId);
          clientName = name ?? 'غير معروف';
        }
        enhanced.add({
          ...collection,
          'ClientName': clientName,
          'BillNumber': collection['Bill'] ?? 'محلية',
          'Amount': collection['Amount'] ?? 0.0,
          'Date': collection['TheDate'] ?? '-',
          'Notes': collection['Notes'] ?? '',
        });
      } catch (_) {
        enhanced.add({
          ...collection,
          'ClientName': 'غير معروف',
          'BillNumber': collection['Bill'] ?? 'محلية',
          'Amount': collection['Amount'] ?? 0.0,
          'Date': collection['TheDate'] ?? '-',
          'Notes': collection['Notes'] ?? '',
        });
      }
    }
    return enhanced;
  }

  Widget _buildCollectionItem(Map<String, dynamic> collection, bool isSynced) {
    final billNumber = collection['BillNumber'] ?? 'محلية';
    final amount = collection['Amount'] ?? 0;
    final date = collection['Date'] ?? '-';
    final clientName = collection['ClientName'] ?? 'غير معروف';
    final notes = collection['Notes'] ?? '';
    final isLocked = collection['Lock'] == 'Lock';

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
            'فاتورة تحصيل #$billNumber',
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
                'العميل: $clientName',
                style: AppStyles.bodySmall(context),
                overflow: TextOverflow.ellipsis,
              ),
              if (notes.isNotEmpty)
                Text(
                  'ملاحظات: $notes',
                  style: AppStyles.bodySmall(context),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
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
                  '$amount ج.م',
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
                builder: (_) => CollectionDetailsScreen(
                  collection: collection,
                  internetAvailable: widget.internetAvailable,
                ),
              ),
            );

            if (result == true) {
              _loadCollections();
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
      appBar: CustomAppBar(
        title: 'التحصيل',
        centerTitle: true,
        elevation: 0,
        actions: [
          ActionButton(
            icon: Icons.sync_rounded,
            label: 'مزامنة',
            onPressed: _syncAllPendingCollections,
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
              MaterialPageRoute(builder: (_) => const NewCollectionScreen()),
            );
            if (created == true) _loadCollections();
          },
          icon: Icon(Icons.add_rounded, size: AppStyles.iconSize(context)),
          label: Text(
            'فاتورة تحصيل جديد',
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
                _buildTabContent(_syncedCollections, _statusSynced, true),
                _buildTabContent(_unsyncedCollections, _statusUnsynced, false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(
    List<Map<String, dynamic>> collections,
    String status,
    bool isSynced,
  ) {
    return TabContentBuilder(
      items: collections,
      status: status,
      isSynced: isSynced,
      emptyIcon: isSynced
          ? Icons.cloud_done_rounded
          : Icons.sync_problem_rounded,
      emptyMessage: isSynced
          ? 'لا توجد فواتير تحصيل متزامنة'
          : 'لا توجد فواتير تحصيل غير متزامنة',
      statusMessage: isSynced
          ? '${collections.length} فاتورة تحصيل متزامن مع الخادم'
          : '${collections.length} فاتورة تحصيل في انتظار المزامنة',
      itemBuilder: (context, collection, isSynced) =>
          _buildCollectionItem(collection, isSynced),
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
          'جاري تحميل فواتير التحصيل...',
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
            onPressed: _loadCollections,
            isLoading: false,
            backgroundColor: AppColors.primary,
          ),
        ],
      ),
    ),
  );
}
