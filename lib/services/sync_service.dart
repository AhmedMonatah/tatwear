import 'remote_db_service.dart';
import 'local_db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  final RemoteDbService _remote = RemoteDbService.instance;
  final LocalDbService _local = LocalDbService.instance;

  final Map<String, List<String>> tableColumns = {
    'Region': ['RegionId', 'Region'],
    'Clients': ['Id', 'Client', 'Phone', 'Address', 'RegionId'],
    'Branchs': ['Id', 'Name'],
    'Sellers': ['Id', 'Seller', 'Phone', 'Address'],
    'STRCategory': ['Id', 'Category'],
    'STRItems': [
      'Id',
      'ItemId',
      'Name',
      'CategoryId',
      'SellingPrice',
      'SellingPriceBig',
      'WholesalePrice',
      'WholesalePriceBig',
      'BuyPrice',
      'BuyPriceBig',
      'UnitQty',
    ],
    'vw_Inventory_AllBranches_Current': [
      'Id',
      'Name',
      'ItemId',
      'BranchName',
      'BranchId',
      'Qty',
      'CategoryId',
      'SellingPrice',
      'SellingPriceBig',
      'WholesalePrice',
      'WholesalePriceBig',
      'BuyPrice',
      'BuyPriceBig',
      'UnitQty',
    ],
    'Settings': ['Id', 'Company', 'Address', 'Phones'],
  };

  Future<double?> getClientBalance(int clientId) async {
    try {
      await _ensureConnection();

      final query =
          "SELECT FinalValue FROM vw_ClientBalance WHERE Id = $clientId";
      final result = await _remote.getData(query);
      final rows = result['rows'] as List<dynamic>? ?? [];

      if (rows.isNotEmpty) {
        final balance = rows.first['FinalValue'];
        if (balance != null) {
          return (balance as num).toDouble();
        }
      }
      return 0.0;
    } catch (e) {
      rethrow;
    }
  }

  Future<double?> getSellerBalance(int sellerId) async {
    try {
      await _ensureConnection();

      final query =
          "SELECT FinalValue FROM vw_SellerBalance WHERE Id = $sellerId";
      final result = await _remote.getData(query);
      final rows = result['rows'] as List<dynamic>? ?? [];

      if (rows.isNotEmpty) {
        final balance = rows.first['FinalValue'];
        if (balance != null) {
          return (balance as num).toDouble();
        }
      }
      return 0.0;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> syncUserData() async {
    try {
      await _syncEssentialTables();
    } catch (e) {
      // Don't rethrow - this is often called during login and shouldn't block the user
    }
  }

  Future<void> _syncEssentialTables() async {
    try {
      final essentialTables = [
        'Clients',
        'Sellers',
        'Region',
        'Branchs',
        'STRItems',
        'STRCategory',
        'Settings',
        'vw_Inventory_AllBranches_Current',
      ];
      for (final table in essentialTables) {
        if (tableColumns.containsKey(table)) {
          await _fetchTableFromServer(table, tableColumns[table]!);
        }
      }
    } catch (e) {
      // Don't rethrow - allow app to continue with local data
    }
  }

  Future<void> _fetchTableFromServer(String table, List<String> columns) async {
    try {
      final columnString = columns.map((c) => '[$c]').join(', ');

      String query;

      // Special handling for inventory view
      if (table == 'vw_Inventory_AllBranches_Current') {
        final prefs = await SharedPreferences.getInstance();
        final branchId = prefs.getInt('branch_id');

        if (branchId == null) {
          throw Exception('BranchId not found in SharedPreferences');
        }

        query =
            'SELECT $columnString FROM [$table] WHERE BranchId = $branchId;';
      } else {
        query = 'SELECT $columnString FROM [$table];';
      }

      final result = await _remote.getData(query);
      final rows = result['rows'] as List<dynamic>? ?? [];

      if (rows.isNotEmpty) {
        await _local.upsertTableWithColumns(table, columns, rows);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getSettings() async {
    try {
      final settings = await _local.getSettings();
      if (settings.isNotEmpty) {
        return settings.first;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchUserSellsBills() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      List<Map<String, dynamic>> serverBills = [];
      bool fromServer = false;

      try {
        await _ensureConnection();

        try {
          await syncPendingToServer();
        } catch (_) {
          // Ignore sync errors
        }

        final query =
            '''
DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE());
DECLARE @CurrentHour INT = DATEPART(HOUR, GETDATE());

DECLARE @StartOfDay DATETIME;
IF @CurrentHour < 4
    SET @StartOfDay = DATEADD(DAY, -1, CONVERT(DATETIME, @CurrentDate));
ELSE
    SET @StartOfDay = CONVERT(DATETIME, @CurrentDate);

DECLARE @EndOfDay DATETIME = DATEADD(DAY, 1, CONVERT(DATETIME, @CurrentDate));

SELECT 
    sb.Id,
    sb.TheDate, 
    sb.Bill, 
    sb.ClientId,
    sb.BranchId,
    sb.UserId,
    sb.Total,
    sb.PaiedForien,
    sb.Discount,
    sb.Rest,
    sb.NetTotal,
    sb.PastAccount,
    sb.GrandTotal,
    sb.Lock,
    sb.Settlement
FROM SellsBills sb
WHERE sb.UserId = $userId
  AND sb.TheDate >= @StartOfDay
  AND sb.TheDate < @EndOfDay
ORDER BY sb.TheDate DESC;
''';

        final result = await _remote.getData(query);
        serverBills = List<Map<String, dynamic>>.from(result['rows'] ?? []);

        if (serverBills.isNotEmpty) {
          await _local.storeSellsBills(serverBills);

          final billIds = serverBills.map((bill) => bill['Id'] as int).toList();

          if (billIds.isNotEmpty) {
            await fetchSellsItemsForBills(billIds);
          }
        }

        fromServer = true;
      } catch (e) {
        fromServer = false;
      }

      final pendingBills = await _local.getPendingSellsBills();

      final allBills = [...pendingBills, ...serverBills];

      return {'bills': allBills, 'fromServer': fromServer};
    } catch (e) {
      final pendingBills = await _local.getPendingSellsBills();
      return {'bills': pendingBills, 'fromServer': false};
    }
  }

  Future<void> fetchSellsItemsForBills(List<int> billIds) async {
    if (billIds.isEmpty) return;

    try {
      await _ensureConnection();
      final billIdsString = billIds.join(',');
      final query =
          '''
      SELECT 
        s.BillId,
        s.ItemId,
        s.Qty,
        s.Price,
        s.Total,
        s.QtyUnit,
        s.Pricing,
        s.Type, 
        s.FirstPrice,
        s.BuyPrice,
        s.UnitQty, 
        s.TotalQty,
        s.ItemBranchId
      FROM Sells s
      WHERE s.BillId IN ($billIdsString)
    ''';

      final result = await _remote.getData(query);
      final rows = List<Map<String, dynamic>>.from(result['rows'] ?? []);
      if (rows.isNotEmpty) {
        await _local.storeSellsItems(rows);
      }
    } catch (e) {
      // Don't rethrow - this is not critical for main functionality
    }
  }

  Future<void> syncPendingToServer() async {
    bool syncStarted = false;
    try {
      await _ensureConnection();
      syncStarted = true;

      // Sync in order of importance
      await _syncPendingBills();
      await _syncPendingSells();
      await _syncPendingBillUpdates();
      await _syncPendingCollections();
      await _syncPendingExchangeItems();
      await _syncPendingCollectionUpdates();
      await _syncPendingBuysBills();
      await _syncPendingBuysBillUpdates();
      await _syncPendingExchangeBills();
      await _syncPendingExchangeBillUpdates();
    } catch (e) {
      if (!syncStarted) {
        throw Exception('Could not start sync due to connection issues');
      }
      rethrow;
    }
  }

  Future<void> _syncPendingBillUpdates() async {
    try {
      final pendingBills = await _local.getPendingUpdatedBills();

      for (final bill in pendingBills) {
        try {
          final billId = bill['Id'] as int;
          final total = bill['Total'] as double;
          final lock = bill['Lock']?.toString();
          final paied = bill['PaiedForien'] as double?;
          final discount = bill['Discount'] as double?;
          final pastAccount = bill['PastAccount'] as double?;
          final netTotal = bill['NetTotal'] as double?;
          final grandTotal = bill['GrandTotal'] as double?;
          final rest = bill['Rest'] as double?;
          final settlement = bill['Settlement']?.toString() ?? 'آجل';

          final items = await _local.getSellItemsByBillId(billId);

          await updateBillOnServer(
            billId,
            total,
            items,
            lock: lock,
            paied: paied,
            discount: discount,
            pastAccount: pastAccount,
            netTotal: netTotal,
            grandTotal: grandTotal,
            rest: rest,
            settlement: settlement,
          );
          await _local.markBillAsSynced(billId);
        } catch (e) {
          // Continue with other bills
          print('Failed to sync bill update: $e');
        }
      }
    } catch (e) {
      // Don't rethrow - allow other sync operations to continue
      print('Error in _syncPendingBillUpdates: $e');
    }
  }

  Future<void> _syncPendingBills() async {
    try {
      final pendingBills = await _local.getPendingSellsBills();

      for (final bill in pendingBills) {
        await _syncSingleBill(bill);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _syncSingleBill(Map<String, dynamic> bill) async {
    try {
      // Check if bill already exists on server
      if (bill['Bill'] != null) {
        final existingQuery =
            "SELECT Id FROM [SellsBills] WHERE Bill = '${bill['Bill']}'";
        final existingResult = await _remote.getData(existingQuery);
        final existingRows = List<Map<String, dynamic>>.from(
          existingResult['rows'] ?? [],
        );

        if (existingRows.isNotEmpty) {
          final existingId = existingRows.first['Id'] as int;
          final items = await _local.getSellItemsByBillId(bill['Id'] as int);
          final lock = bill['Lock']?.toString();
          final settlement = bill['Settlement']?.toString() ?? 'آجل';
          final paied = bill['PaiedForien'] as double?;
          final discount = bill['Discount'] as double?;
          final pastAccount = bill['PastAccount'] as double?;
          final netTotal = bill['NetTotal'] as double?;
          final grandTotal = bill['GrandTotal'] as double?;
          final rest = bill['Rest'] as double?;
          await updateBillOnServer(
            existingId,
            bill['Total'] as double,
            items,
            lock: lock,
            settlement: settlement,
            paied: paied,
            discount: discount,
            pastAccount: pastAccount,
            netTotal: netTotal,
            grandTotal: grandTotal,
            rest: rest,
          );
          await _local.markBillAsSynced(bill['Id'] as int);
          return;
        }
      }

      // Get next bill number
      final maxQuery =
          "SELECT MAX(CAST(Bill AS INT)) AS MaxBill FROM [SellsBills]";
      final maxResult = await _remote.getData(maxQuery);
      final rows = List<Map<String, dynamic>>.from(maxResult['rows'] ?? []);

      int maxBillInt = 0;
      if (rows.isNotEmpty && rows.first['MaxBill'] != null) {
        maxBillInt = int.tryParse(rows.first['MaxBill'].toString()) ?? 0;
      }

      final newBillInt = maxBillInt + 1;
      final newBill = newBillInt.toString();

      // Insert new bill
      final query = _buildBillInsertQuery(bill, newBill);
      final result = await _remote.getData(query);

      // Update local bill with server ID
      final insertRows = List<Map<String, dynamic>>.from(result['rows'] ?? []);
      if (insertRows.isNotEmpty) {
        final inserted = insertRows.first;
        final newId = inserted['Id'] as int?;
        final localUuid = bill['LocalUuid']?.toString();

        if (newId != null && localUuid != null) {
          await _local.updateBillIdAndNumberByLocalUuid(
            localUuid,
            newId,
            newBill,
          );
        }
      } else if (_isSuccessResult(result)) {
        // Fallback marking
        await _local.markSellsBillSynced(bill['Bill'] ?? newBill);
      }
    } catch (e) {
      throw Exception('Failed to sync bill: $e');
    }
  }

  // Update the updateBillOnServer method to include all new fields
  Future<void> updateBillOnServer(
    int billId,
    double total,
    List<Map<String, dynamic>> items, {
    double? paied,
    String? lock,
    double? pastAccount,
    double? netTotal,
    double? discount,
    double? rest,
    double? grandTotal,
    String? settlement,
  }) async {
    try {
      // Update bill with all fields
      final updateBillQuery =
          '''
      UPDATE [SellsBills] SET 
        Total = $total, 
        PaiedForien = ${paied ?? 'NULL'}, 
        Lock = ${lock != null ? "N'${_escapeSqlString(lock)}'" : 'NULL'},
        PastAccount = ${pastAccount ?? 'NULL'},
        NetTotal = ${netTotal ?? 'NULL'},
        Discount = ${discount ?? 'NULL'},
        Rest = ${rest ?? 'NULL'},
        GrandTotal = ${grandTotal ?? 'NULL'},
        Settlement = ${settlement != null ? "N'${_escapeSqlString(settlement)}'" : "N'آجل'"} 
      WHERE Id = $billId
    ''';

      await _remote.writeData(updateBillQuery);

      // Update items
      final deleteItemsQuery = "DELETE FROM [Sells] WHERE BillId = $billId";
      await _remote.writeData(deleteItemsQuery);

      for (final item in items) {
        final sellData = {...item, 'BillId': billId};
        final query = _buildSellInsertQuery(sellData);
        await _remote.writeData(query);
      }
    } catch (e) {
      rethrow;
    }
  }

  String _buildBillInsertQuery(Map<String, dynamic> bill, String billNum) {
    final theDate = bill['TheDate'] ?? '';
    final clientId = bill['ClientId'] ?? 'NULL';
    final branchId = bill['BranchId'] ?? 'NULL';
    final userId = bill['UserId'] ?? 'NULL';
    final total = bill['Total'] ?? 'NULL';
    final paied = bill['PaiedForien'] ?? 'NULL';

    final lock = bill['Lock'] != null
        ? "N'${_escapeSqlString(bill['Lock'].toString())}'"
        : 'NULL';

    final pastAccount = bill['PastAccount'] ?? 'NULL';
    final netTotal = bill['NetTotal'] ?? 'NULL';
    final discount = bill['Discount'] ?? 'NULL';
    final rest = bill['Rest'] ?? 'NULL';
    final grandTotal = bill['GrandTotal'] ?? 'NULL';
    final settlement = bill['Settlement'] != null
        ? "N'${_escapeSqlString(bill['Settlement'].toString())}'"
        : "N'آجل'";

    return '''
DECLARE @Inserted TABLE (Id INT);

INSERT INTO [SellsBills] (
    TheDate,
    Bill,
    ClientId,
    BranchId,
    UserId,
    Total,
    PaiedForien,
    Lock,
    PastAccount,
    NetTotal,
    Discount,
    Rest,
    GrandTotal,
    Settlement  
)
OUTPUT INSERTED.Id INTO @Inserted(Id)
VALUES (
    CONVERT(datetime, '$theDate', 120),
    '$billNum',
    $clientId,
    $branchId,
    $userId,
    $total,
    $paied,
    $lock,
    $pastAccount,
    $netTotal,
    $discount,
    $rest,
    $grandTotal,
    $settlement 
);

SELECT Id FROM @Inserted;
''';
  }

  Future<void> _syncPendingSells() async {
    try {
      final pendingSells = await _local.getPendingSells();

      for (final sell in pendingSells) {
        await _syncSingleSell(sell);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _syncSingleSell(Map<String, dynamic> sell) async {
    try {
      final query = _buildSellInsertQuery(sell);
      await _remote.writeData(query);
      await _local.markSellsSynced(sell['BillId']);
    } catch (e) {
      throw Exception('Failed to sync sell item: $e');
    }
  }

  String _buildSellInsertQuery(Map<String, dynamic> sell) {
    final billId = sell['BillId'] ?? 'NULL';
    final itemId = sell['ItemId'] ?? 'NULL';
    final qty = sell['Qty'] ?? 'NULL';
    final price = sell['Price'] ?? 'NULL';
    final total = sell['Total'] ?? 'NULL';

    final qtyUnit = sell['QtyUnit'] != null
        ? "N'${_escapeSqlString(sell['QtyUnit'].toString())}'"
        : 'NULL';
    final pricing = sell['Pricing'] != null
        ? "N'${_escapeSqlString(sell['Pricing'].toString())}'"
        : 'NULL';
    final type = sell['Type'] != null
        ? "N'${_escapeSqlString(sell['Type'].toString())}'"
        : "N'بيع'";
    final firstPrice = sell['FirstPrice'] ?? price;
    final buyPrice = sell['BuyPrice'] ?? 'NULL';
    final unitQty = sell['UnitQty'] ?? 'NULL';
    final totalQty = sell['TotalQty'] ?? 'NULL';
    final itemBranchId = sell['ItemBranchId'] ?? 'NULL';

    return '''
    INSERT INTO [Sells] (BillId, ItemId, Qty, Price, Total, QtyUnit, Pricing, Type, FirstPrice, BuyPrice, UnitQty, TotalQty, ItemBranchId)
    VALUES ($billId, $itemId, $qty, $price, $total, $qtyUnit, $pricing, $type, $firstPrice, $buyPrice, $unitQty, $totalQty, $itemBranchId);
  ''';
  }

  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  //! EXCHANGE AND EXCHANGE BILLS
  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  Future<Map<String, dynamic>> fetchUserExchangeBills() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      List<Map<String, dynamic>> serverBills = [];
      bool fromServer = false;

      try {
        await _ensureConnection();

        // Sync any pending bills before fetching
        try {
          await syncPendingExchangeToServer();
        } catch (_) {
          // Ignore sync errors
        }

        // Query bills from the last 24 hours (starting at 4 AM)
        final query =
            '''
DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE());
DECLARE @CurrentHour INT = DATEPART(HOUR, GETDATE());

DECLARE @StartOfDay DATETIME;
IF @CurrentHour < 4
    SET @StartOfDay = DATEADD(DAY, -1, CONVERT(DATETIME, @CurrentDate));
ELSE
    SET @StartOfDay = CONVERT(DATETIME, @CurrentDate);

DECLARE @EndOfDay DATETIME = DATEADD(DAY, 1, CONVERT(DATETIME, @CurrentDate));

SELECT 
    eb.Id,
    eb.TheDate,
    eb.Bill,
    eb.UserId,
    eb.Total,
    eb.BranchId,
    eb.DestBranchId,
    eb.Lock
FROM ExchangeBills eb
WHERE eb.UserId = $userId
  AND eb.TheDate >= @StartOfDay
  AND eb.TheDate < @EndOfDay
ORDER BY eb.TheDate DESC;
''';

        final result = await _remote.getData(query);
        serverBills = List<Map<String, dynamic>>.from(result['rows'] ?? []);

        if (serverBills.isNotEmpty) {
          await _local.storeExchangeBills(serverBills);

          final billIds = serverBills.map((bill) => bill['Id'] as int).toList();
          if (billIds.isNotEmpty) {
            await fetchExchangeItemsForBills(billIds);
          }
        }

        fromServer = true;
      } catch (e) {
        fromServer = false;
      }

      final pendingBills = await _local.getPendingExchangeBills();
      final allBills = [...pendingBills, ...serverBills];

      return {'bills': allBills, 'fromServer': fromServer};
    } catch (e) {
      final pendingBills = await _local.getPendingExchangeBills();
      return {'bills': pendingBills, 'fromServer': false};
    }
  }

  /// Fetches exchange items (details) for a list of bill IDs.
  Future<void> fetchExchangeItemsForBills(List<int> billIds) async {
    if (billIds.isEmpty) return;

    try {
      await _ensureConnection();
      final billIdsString = billIds.join(',');
      final query =
          '''
SELECT 
    BillId,
    Qty,
    QtyUnit,
    Price,
    Total,
    ItemId,
    UnitQty,
    TotalQty,
    BranchId,
    DestBranchId
FROM Exchange
WHERE BillId IN ($billIdsString)
''';

      final result = await _remote.getData(query);
      final rows = List<Map<String, dynamic>>.from(result['rows'] ?? []);
      if (rows.isNotEmpty) {
        await _local.storeExchangeItems(rows);
      }
    } catch (e) {
      // Non-critical, do not rethrow
    }
  }

  /// Sync all pending exchange data (bills and items) to the server.
  Future<void> syncPendingExchangeToServer() async {
    bool syncStarted = false;
    try {
      await _ensureConnection();
      syncStarted = true;

      await _syncPendingExchangeBills();
      await _syncPendingExchangeItems();
      await _syncPendingExchangeBillUpdates();
    } catch (e) {
      if (!syncStarted) {
        throw Exception('Could not start sync due to connection issues');
      }
      rethrow;
    }
  }

  /// Sync updated exchange bills (modifications) to the server.
  Future<void> _syncPendingExchangeBillUpdates() async {
    try {
      final pendingBills = await _local.getPendingUpdatedExchangeBills();

      for (final bill in pendingBills) {
        try {
          final billId = bill['Id'] as int;
          final total = bill['Total'] as double;
          final items = await _local.getExchangeItemsByBillId(billId);
          final lock = bill['Lock']?.toString();

          await updateExchangeBillOnServer(billId, total, items, lock);
          await _local.markExchangeBillAsSynced(billId);
        } catch (e) {
          print('Failed to sync exchange bill update: $e');
        }
      }
    } catch (e) {
      print('Error in _syncPendingExchangeBillUpdates: $e');
    }
  }

  /// Sync new exchange bills (headers) to the server.
  Future<void> _syncPendingExchangeBills() async {
    try {
      final pendingBills = await _local.getPendingExchangeBills();

      for (final bill in pendingBills) {
        await _syncSingleExchangeBill(bill);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Sync a single exchange bill to the server (insert or update if already exists).
  Future<void> _syncSingleExchangeBill(Map<String, dynamic> bill) async {
    try {
      // Check if bill already exists on server (by Bill number)
      if (bill['Bill'] != null) {
        final existingQuery =
            "SELECT Id FROM [ExchangeBills] WHERE Bill = '${bill['Bill']}'";
        final existingResult = await _remote.getData(existingQuery);
        final existingRows = List<Map<String, dynamic>>.from(
          existingResult['rows'] ?? [],
        );

        if (existingRows.isNotEmpty) {
          final existingId = existingRows.first['Id'] as int;
          final items = await _local.getExchangeItemsByBillId(
            bill['Id'] as int,
          );
          final lock = bill['Lock']?.toString();
          await updateExchangeBillOnServer(
            existingId,
            bill['Total'] as double,
            items,
            lock,
          );
          await _local.markExchangeBillAsSynced(bill['Id'] as int);
          return;
        }
      }

      // Get next bill number
      final maxQuery =
          "SELECT MAX(CAST(Bill AS INT)) AS MaxBill FROM [ExchangeBills]";
      final maxResult = await _remote.getData(maxQuery);
      final rows = List<Map<String, dynamic>>.from(maxResult['rows'] ?? []);

      int maxBillInt = 0;
      if (rows.isNotEmpty && rows.first['MaxBill'] != null) {
        maxBillInt = int.tryParse(rows.first['MaxBill'].toString()) ?? 0;
      }

      final newBillInt = maxBillInt + 1;
      final newBill = newBillInt.toString();

      // Insert new bill
      final query = _buildExchangeBillInsertQuery(bill, newBill);
      final result = await _remote.getData(query);

      // Update local bill with server ID
      final insertRows = List<Map<String, dynamic>>.from(result['rows'] ?? []);
      if (insertRows.isNotEmpty) {
        final inserted = insertRows.first;
        final newId = inserted['Id'] as int?;
        final localUuid = bill['LocalUuid']?.toString();

        if (newId != null && localUuid != null) {
          await _local.updateExchangeBillIdAndNumberByLocalUuid(
            localUuid,
            newId,
            newBill,
          );
        }
      } else if (_isSuccessResult(result)) {
        await _local.markExchangeBillSynced(bill['Bill'] ?? newBill);
      }
    } catch (e) {
      throw Exception('Failed to sync exchange bill: $e');
    }
  }

  /// Sync pending exchange items (details) to the server.
  Future<void> _syncPendingExchangeItems() async {
    try {
      final pendingItems = await _local.getPendingExchangeItems();

      for (final item in pendingItems) {
        await _syncSingleExchangeItem(item);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Sync a single exchange item to the server.
  Future<void> _syncSingleExchangeItem(Map<String, dynamic> item) async {
    try {
      final query = _buildExchangeItemInsertQuery(item);
      await _remote.writeData(query);
      await _local.markExchangeItemsSynced(item['BillId']);
    } catch (e) {
      throw Exception('Failed to sync exchange item: $e');
    }
  }

  /// Updates an existing exchange bill on the server.
  Future<void> updateExchangeBillOnServer(
    int billId,
    double total,
    List<Map<String, dynamic>> items,
    String? lock,
  ) async {
    try {
      // Update bill header
      final updateBillQuery =
          '''
UPDATE [ExchangeBills] SET 
    Total = $total,
    Lock = ${lock != null ? "N'${_escapeSqlString(lock)}'" : 'NULL'}
WHERE Id = $billId
''';
      await _remote.writeData(updateBillQuery);

      // Replace all items for this bill
      final deleteItemsQuery = "DELETE FROM [Exchange] WHERE BillId = $billId";
      await _remote.writeData(deleteItemsQuery);

      for (final item in items) {
        final itemData = {...item, 'BillId': billId};
        final query = _buildExchangeItemInsertQuery(itemData);
        await _remote.writeData(query);
      }
    } catch (e) {
      rethrow;
    }
  }

  // ==============================
  // SQL QUERY BUILDERS
  // ==============================

  /// Builds an INSERT statement for an exchange bill header.
  String _buildExchangeBillInsertQuery(
    Map<String, dynamic> bill,
    String billNum,
  ) {
    final theDate = bill['TheDate'] ?? '';
    final userId = bill['UserId'] ?? 'NULL';
    final total = bill['Total'] ?? 'NULL';
    final branchId = bill['BranchId'] ?? 'NULL';
    final destBranchId = bill['DestBranchId'] ?? 'NULL';
    final lock = bill['Lock'] != null
        ? "N'${_escapeSqlString(bill['Lock'].toString())}'"
        : 'NULL';
    return '''
DECLARE @Inserted TABLE (Id INT);

INSERT INTO [ExchangeBills] (
    TheDate,
    Bill,
    UserId,
    Total,
    BranchId,
    DestBranchId,
    Lock
)
OUTPUT INSERTED.Id INTO @Inserted(Id)
VALUES (
    CONVERT(datetime, '$theDate', 120),
    '$billNum',
    $userId,
    $total,
    $branchId,
    $destBranchId,
    $lock
);

SELECT Id FROM @Inserted;
''';
  }

  /// Builds an INSERT statement for an exchange item (detail).
  String _buildExchangeItemInsertQuery(Map<String, dynamic> item) {
    final billId = item['BillId'] ?? 'NULL';
    final qty = item['Qty'] ?? 'NULL';
    final qtyUnit = item['QtyUnit'] != null
        ? "N'${_escapeSqlString(item['QtyUnit'].toString())}'"
        : 'NULL';
    final price = item['Price'] ?? 'NULL';
    final total = item['Total'] ?? 'NULL';
    final itemId = item['ItemId'] ?? 'NULL';
    final unitQty = item['UnitQty'] ?? 'NULL';
    final totalQty = item['TotalQty'] ?? 'NULL';
    final branchId = item['BranchId'] ?? 'NULL';
    final destBranchId = item['DestBranchId'] ?? 'NULL';

    return '''
INSERT INTO [Exchange] (
    BillId, Qty, QtyUnit, Price, Total, ItemId, UnitQty, TotalQty, BranchId, DestBranchId
) VALUES (
    $billId, $qty, $qtyUnit, $price, $total, $itemId, $unitQty, $totalQty, $branchId, $destBranchId
);
''';
  }

  //! COLLECTION METHODS - UPDATED WITH SEPARATE UPDATE SYNC
  Future<Map<String, dynamic>> fetchUserCollections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      List<Map<String, dynamic>> serverCollections = [];
      bool fromServer = false;

      try {
        await _ensureConnection();

        // Try to sync any pending local collections to the server
        try {
          await syncPendingCollectionsToServer();
        } catch (_) {
          // Ignore sync errors, continue fetching from server
        }

        final query =
            '''
DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE());
DECLARE @CurrentHour INT = DATEPART(HOUR, GETDATE());

DECLARE @StartOfDay DATETIME;
IF @CurrentHour < 4
    SET @StartOfDay = DATEADD(DAY, -1, CONVERT(DATETIME, @CurrentDate));
ELSE
    SET @StartOfDay = CONVERT(DATETIME, @CurrentDate);

DECLARE @EndOfDay DATETIME = DATEADD(DAY, 1, CONVERT(DATETIME, @CurrentDate));

SELECT 
  cp.Id,
  cp.ClientId,
  cp.TheDate, 
  cp.Bill, 
  cp.Amount,
  cp.BranchId,
  cp.UserId,
  cp.Notes,
  cp.Lock
FROM ClientsPaying cp
WHERE cp.UserId = $userId
  AND cp.TheDate >= @StartOfDay
  AND cp.TheDate <  @EndOfDay
ORDER BY cp.TheDate DESC;
''';

        final result = await _remote.getData(query);

        serverCollections = List<Map<String, dynamic>>.from(
          result['rows'] ?? [],
        );

        // If server returned data, store it locally
        if (serverCollections.isNotEmpty) {
          await _local.storeCollections(serverCollections);
        }

        fromServer = true;
      } catch (e) {
        fromServer = false;
      }

      // Get locally pending collections
      final pendingCollections = await _local.getPendingCollections();

      // Combine local pending + server data
      final allCollections = [...pendingCollections, ...serverCollections];

      return {'collections': allCollections, 'fromServer': fromServer};
    } catch (e) {
      // Fallback: only local data
      final pendingCollections = await _local.getPendingCollections();

      return {'collections': pendingCollections, 'fromServer': false};
    }
  }

  Future<void> syncPendingCollectionsToServer() async {
    bool syncStarted = false;
    try {
      await _ensureConnection();
      syncStarted = true;
      await _syncPendingCollections();
      await _syncPendingCollectionUpdates(); // NEW: Add collection updates
    } catch (e) {
      if (!syncStarted) {
        throw Exception('Could not start sync due to connection issues');
      }
      rethrow;
    }
  }

  Future<void> _syncPendingCollections() async {
    try {
      final pendingCollections = await _local.getPendingCollections();

      for (final collection in pendingCollections) {
        await _syncSingleCollection(collection);
      }
    } catch (e) {
      rethrow;
    }
  }

  // NEW: Method to sync collection updates
  Future<void> _syncPendingCollectionUpdates() async {
    try {
      final pendingCollections = await _local.getPendingUpdatedCollections();

      for (final collection in pendingCollections) {
        try {
          final collectionId = collection['Id'] as int;
          final amount = collection['Amount'] as double;
          final notes = collection['Notes']?.toString() ?? '';
          final lock = collection['Lock']?.toString();

          await updateCollectionOnServer(
            collectionId,
            amount,
            notes,
            lock: lock,
          );
          await _local.markCollectionAsSynced(collectionId);
        } catch (e) {
          // Continue with other collections
          print('Failed to sync collection update: $e');
        }
      }
    } catch (e) {
      // Don't rethrow - allow other sync operations to continue
      print('Error in _syncPendingCollectionUpdates: $e');
    }
  }

  Future<void> _syncSingleCollection(Map<String, dynamic> collection) async {
    try {
      // Check if collection already exists on server
      if (collection['Bill'] != null) {
        final existingQuery =
            "SELECT Id FROM [ClientsPaying] WHERE Bill = '${collection['Bill']}'";
        final existingResult = await _remote.getData(existingQuery);
        final existingRows = List<Map<String, dynamic>>.from(
          existingResult['rows'] ?? [],
        );

        if (existingRows.isNotEmpty) {
          final existingId = existingRows.first['Id'] as int;
          await updateCollectionOnServer(
            existingId,
            collection['Amount'] as double,
            collection['Notes']?.toString() ?? '',
          );
          await _local.markCollectionAsSynced(collection['Id'] as int);
          return;
        }
      }

      // Get next collection number
      final maxQuery =
          "SELECT MAX(CAST(Bill AS INT)) AS MaxBill FROM [ClientsPaying]";
      final maxResult = await _remote.getData(maxQuery);
      final rows = List<Map<String, dynamic>>.from(maxResult['rows'] ?? []);

      int maxBillInt = 0;
      if (rows.isNotEmpty && rows.first['MaxBill'] != null) {
        maxBillInt = int.tryParse(rows.first['MaxBill'].toString()) ?? 0;
      }

      final newBillInt = maxBillInt + 1;
      final newBill = newBillInt.toString();

      // Insert new collection
      final query = _buildCollectionInsertQuery(collection, newBill);
      final result = await _remote.getData(query);

      // Update local collection with server ID
      final insertRows = List<Map<String, dynamic>>.from(result['rows'] ?? []);
      if (insertRows.isNotEmpty) {
        final inserted = insertRows.first;
        final newId = inserted['Id'] as int?;
        final localUuid = collection['LocalUuid']?.toString();

        if (newId != null && localUuid != null) {
          await _local.updateCollectionIdAndNumberByLocalUuid(
            localUuid,
            newId,
            newBill,
          );
        }
      } else if (_isSuccessResult(result)) {
        // Fallback marking
        await _local.markCollectionAsSynced(collection['Id'] as int);
      }
    } catch (e) {
      throw Exception('Failed to sync collection: $e');
    }
  }

  Future<void> updateCollectionOnServer(
    int collectionId,
    double amount,
    String notes, {
    String? lock,
  }) async {
    try {
      final lockValue = lock != null ? "N'${_escapeSqlString(lock)}'" : 'NULL';
      final updateQuery =
          '''
      UPDATE [ClientsPaying] SET 
        Amount = $amount, 
        Notes = ${notes.isNotEmpty ? "N'${_escapeSqlString(notes)}'" : 'NULL'},
        Lock = $lockValue
      WHERE Id = $collectionId
    ''';

      await _remote.writeData(updateQuery);
    } catch (e) {
      rethrow;
    }
  }

  String _buildCollectionInsertQuery(
    Map<String, dynamic> collection,
    String billNum,
  ) {
    final theDate = collection['TheDate'] ?? '';
    final clientId = collection['ClientId'] ?? 'NULL';
    final amount = collection['Amount'] ?? 'NULL';
    final branchId = collection['BranchId'] ?? 'NULL';
    final userId = collection['UserId'] ?? 'NULL';
    final notes = collection['Notes'] != null
        ? "N'${_escapeSqlString(collection['Notes'].toString())}'"
        : 'NULL';
    final lock = collection['Lock'] != null
        ? "N'${_escapeSqlString(collection['Lock'].toString())}'"
        : 'NULL';

    return '''
DECLARE @Inserted TABLE (Id INT);

INSERT INTO [ClientsPaying] (
    TheDate,
    Bill,
    ClientId,
    Amount,
    BranchId,
    UserId,
    Notes,
    Lock
)
OUTPUT INSERTED.Id INTO @Inserted(Id)
VALUES (
    CONVERT(datetime, '$theDate', 120),
    '$billNum',
    $clientId,
    $amount,
    $branchId,
    $userId,
    $notes,
    $lock
);

SELECT Id FROM @Inserted;
''';
  }

  String _escapeSqlString(String text) {
    return text.replaceAll("'", "''");
  }

  //!  BUYS AND BUYSBILLS
  // ==================== BUYS BILLS FUNCTIONS ====================

  Future<Map<String, dynamic>> fetchUserBuysBills() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      List<Map<String, dynamic>> serverBills = [];
      bool fromServer = false;

      try {
        await _ensureConnection();

        try {
          await syncPendingBuysToServer();
        } catch (_) {
          // Ignore sync errors
        }

        final query =
            '''
DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE());
DECLARE @CurrentHour INT = DATEPART(HOUR, GETDATE());

DECLARE @StartOfDay DATETIME;
IF @CurrentHour < 4
    SET @StartOfDay = DATEADD(DAY, -1, CONVERT(DATETIME, @CurrentDate));
ELSE
    SET @StartOfDay = CONVERT(DATETIME, @CurrentDate);

DECLARE @EndOfDay DATETIME = DATEADD(DAY, 1, CONVERT(DATETIME, @CurrentDate));

SELECT 
    bb.Id,
    bb.TheDate, 
    bb.Bill, 
    bb.SellerId,
    bb.BranchId,
    bb.UserId,
    bb.Total,
    bb.Paied,      
    bb.Discount,
    bb.NetTotal,
    bb.PastAccount,
    bb.Rest,         
    bb.GrandTotal,
    bb.Lock,
    bb.Type
FROM BuysBills bb
WHERE bb.UserId = $userId
  AND bb.TheDate >= @StartOfDay
  AND bb.TheDate < @EndOfDay
ORDER BY bb.TheDate DESC;
''';

        final result = await _remote.getData(query);
        serverBills = List<Map<String, dynamic>>.from(result['rows'] ?? []);

        if (serverBills.isNotEmpty) {
          await _local.storeBuysBills(serverBills);

          final billIds = serverBills.map((bill) => bill['Id'] as int).toList();

          if (billIds.isNotEmpty) {
            await fetchBuysItemsForBills(billIds);
          }
        }

        fromServer = true;
      } catch (e) {
        fromServer = false;
      }

      final pendingBills = await _local.getPendingBuysBills();

      final allBills = [...pendingBills, ...serverBills];

      return {'bills': allBills, 'fromServer': fromServer};
    } catch (e) {
      final pendingBills = await _local.getPendingBuysBills();
      return {'bills': pendingBills, 'fromServer': false};
    }
  }

  Future<void> fetchBuysItemsForBills(List<int> billIds) async {
    if (billIds.isEmpty) return;

    try {
      await _ensureConnection();
      final billIdsString = billIds.join(',');
      final query =
          '''
      SELECT 
        b.BillId,
        b.ItemId,
        b.Qty,
        b.Price,
        b.Total,
        b.QtyUnit,
        b.Type,
        b.FirstPrice,
        b.UnitQty, 
        b.TotalQty,
        b.Serial, 
        b.SerialType 
      FROM Buys b
      WHERE b.BillId IN ($billIdsString)
    ''';

      final result = await _remote.getData(query);
      final rows = List<Map<String, dynamic>>.from(result['rows'] ?? []);
      if (rows.isNotEmpty) {
        await _local.storeBuysItems(rows);
      }
    } catch (e) {
      // Don't rethrow - this is not critical for main functionality
    }
  }

  Future<void> syncPendingBuysToServer() async {
    bool syncStarted = false;
    try {
      await _ensureConnection();
      syncStarted = true;

      // Sync in order of importance
      await _syncPendingBuysBills();
      await _syncPendingBuysBillUpdates();
    } catch (e) {
      if (!syncStarted) {
        throw Exception('Could not start sync due to connection issues');
      }
      rethrow;
    }
  }

  Future<void> _syncPendingBuysBillUpdates() async {
    try {
      final pendingBills = await _local.getPendingUpdatedBuysBills();

      for (final bill in pendingBills) {
        try {
          final billId = bill['Id'] as int;
          final total = bill['Total'] as double;
          final lock = bill['Lock']?.toString();
          final discount = bill['Discount'] as double?;
          final paied = bill['Paied'] as double?;
          final pastAccount = bill['PastAccount'] as double?;
          final netTotal = bill['NetTotal'] as double?;
          final grandTotal = bill['GrandTotal'] as double?;
          final type = bill['Type']?.toString() ?? 'شراء';

          final items = await _local.getBuysItemsByBillId(billId);

          await updateBuysBillOnServer(
            billId,
            total,
            items,
            lock: lock,
            discount: discount,
            pastAccount: pastAccount,
            netTotal: netTotal,
            grandTotal: grandTotal,
            type: type,
            paied: paied,
          );
          await _local.markBuysBillAsSynced(billId);
        } catch (e) {
          // Continue with other bills
          print('Failed to sync buys bill update: $e');
        }
      }
    } catch (e) {
      // Don't rethrow - allow other sync operations to continue
      print('Error in _syncPendingBuysBillUpdates: $e');
    }
  }

  Future<void> _syncPendingBuysBills() async {
    try {
      final pendingBills = await _local.getPendingBuysBills();

      for (final bill in pendingBills) {
        await _syncSingleBuysBill(bill);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _syncSingleBuysBill(Map<String, dynamic> bill) async {
    try {
      int? newId;
      String? newBill;
      final localUuid = bill['LocalUuid']?.toString();

      // Check if bill already exists on server by Bill number (not Serial)
      if (bill['Bill'] != null) {
        final existingQuery =
            "SELECT Id FROM [BuysBills] WHERE Bill = '${bill['Bill']}'";
        final existingResult = await _remote.getData(existingQuery);
        final existingRows = List<Map<String, dynamic>>.from(
          existingResult['rows'] ?? [],
        );

        if (existingRows.isNotEmpty) {
          final existingId = existingRows.first['Id'] as int;
          final items = await _local.getBuysItemsByBillId(bill['Id'] as int);
          final lock = bill['Lock']?.toString();
          final type = bill['Type']?.toString() ?? 'شراء';
          final paied = bill['Paied'] as double?;
          final discount = bill['Discount'] as double?;
          final pastAccount = bill['PastAccount'] as double?;
          final netTotal = bill['NetTotal'] as double?;
          final grandTotal = bill['GrandTotal'] as double?;
          final rest = bill['Rest'] as double?;
          await updateBuysBillOnServer(
            existingId,
            bill['Total'] as double,
            items,
            lock: lock,
            type: type,
            paied: paied,
            discount: discount,
            pastAccount: pastAccount,
            netTotal: netTotal,
            grandTotal: grandTotal,
            rest: rest,
          );
          await _local.markBuysBillAsSynced(bill['Id'] as int);
          return;
        }
      }

      // Get next bill number (not serial)
      final maxBillQuery =
          "SELECT MAX(CAST(Bill AS INT)) AS MaxBill FROM [BuysBills]";
      final maxBillResult = await _remote.getData(maxBillQuery);
      final billRows = List<Map<String, dynamic>>.from(
        maxBillResult['rows'] ?? [],
      );

      int maxBillInt = 0;
      if (billRows.isNotEmpty && billRows.first['MaxBill'] != null) {
        maxBillInt = int.tryParse(billRows.first['MaxBill'].toString()) ?? 0;
      }

      final newBillInt = maxBillInt + 1;
      newBill = newBillInt.toString();

      // Insert new bill (without Serial - Serial goes in Buys table items)
      final query = _buildBuysBillInsertQuery(bill, newBill);
      final result = await _remote.getData(query);

      // Update local bill with server ID
      final insertRows = List<Map<String, dynamic>>.from(result['rows'] ?? []);
      if (insertRows.isNotEmpty) {
        final inserted = insertRows.first;
        newId = inserted['Id'] as int?;

        if (newId != null && localUuid != null) {
          await _local.updateBuysBillIdAndNumberByLocalUuid(
            localUuid,
            newId,
            newBill,
          );
        }
      } else if (_isSuccessResult(result)) {
        // Fallback marking
        await _local.markBuysBillSynced(bill['Bill'] ?? newBill);
      }

      if (newId != null && localUuid != null) {
        // Sync items for this bill
        final items = await _local.getBuysItemsByLocalUuid(localUuid);
        for (final item in items) {
          var buyItem = Map<String, dynamic>.from(item);
          var serial = buyItem['Serial']?.toString();

          if (serial == null || serial.isEmpty) {
            print('Fetching new serial for buy item');

            try {
              final serialResult = await _remote.getData(
                "SELECT NewSerial FROM GetNewSerial",
              );
              final rows = serialResult['rows'] as List<dynamic>? ?? [];

              if (rows.isNotEmpty) {
                final fetchedSerial = rows.first['NewSerial'];
                final intSerial = int.tryParse(fetchedSerial.toString()) ?? 0;

                print('Serial before increment: $intSerial');

                var incrementedSerial = intSerial + 1;

                print('Serial after increment: $incrementedSerial');
                print("item before update serial :");
                print(buyItem);
                serial = incrementedSerial.toString();
                print("Serial after convert to string : $serial");

                buyItem['Serial'] = serial;
                print("item after update serial :");
                print(buyItem);
                print('New incremented serial: $serial');
              } else {
                print('Failed to fetch new serial');
                throw Exception('Failed to get new serial');
              }
            } catch (e) {
              print('Error fetching serial: $e');
              throw Exception('Failed to get new serial: $e');
            }
          } else {
            print('Using existing serial: $serial');
          }

          print('Full data of sending buy item: $buyItem');

          final buyData = {...buyItem, 'BillId': newId};
          final insertQuery = _buildBuysInsertQuery(buyData);

          print('Insert query for buy item: $insertQuery');

          try {
            await _remote.writeData(insertQuery);
          } catch (writeError) {
            print('Error writing buy item to database: $writeError');
          }

          // Update local with new serial and type
          await _local.updateBuySerial(
            newId,
            item['ItemId'] as int,
            serial,
            'Automatic',
          );
        }

        // Mark as synced after all items
        await _local.markBuysBillAsSynced(newId);
        await _local.markBuysSynced(newId);
      }
    } catch (e) {
      throw Exception('Failed to sync buys bill: $e');
    }
  }

  Future<void> updateBuysBillOnServer(
    int billId,
    double total,
    List<Map<String, dynamic>> items, {
    double? paied,
    String? lock,
    double? pastAccount,
    double? netTotal,
    double? discount,
    double? rest,
    double? grandTotal,
    String? type,
  }) async {
    try {
      final updateBillQuery =
          '''
      UPDATE [BuysBills] SET 
        Total = $total, 
        Paied = ${paied ?? 'NULL'},           
        Lock = ${lock != null ? "N'${_escapeSqlString(lock)}'" : 'NULL'},
        PastAccount = ${pastAccount ?? 'NULL'},
        NetTotal = ${netTotal ?? 'NULL'},
        Discount = ${discount ?? 'NULL'},
        Rest = ${rest ?? 'NULL'},            
        GrandTotal = ${grandTotal ?? 'NULL'},
        Type = ${type != null ? "N'${_escapeSqlString(type)}'" : "N'شراء'"} 
      WHERE Id = $billId
    ''';

      await _remote.writeData(updateBillQuery);

      final deleteItemsQuery = "DELETE FROM [Buys] WHERE BillId = $billId";
      await _remote.writeData(deleteItemsQuery);

      for (final item in items) {
        var buyItem = Map<String, dynamic>.from(item);
        String? serial = buyItem['Serial']?.toString();

        if (serial == null || serial.isEmpty) {
          print('Fetching new serial for updated buy item');

          try {
            final serialResult = await _remote.getData(
              "SELECT NewSerial FROM GetNewSerial",
            );
            final rows = serialResult['rows'] as List<dynamic>? ?? [];

            if (rows.isNotEmpty) {
              final fetchedSerial = rows.first['NewSerial'];
              final intSerial = int.tryParse(fetchedSerial.toString()) ?? 0;

              print('Serial before increment: $intSerial');

              final incrementedSerial = intSerial + 1;

              print('Serial after increment: $incrementedSerial');

              serial = incrementedSerial.toString();
              buyItem['Serial'] = serial;

              print('New incremented serial for updated item: $serial');
            } else {
              print('Failed to fetch new serial for updated item');
              throw Exception('Failed to get new serial for updated item');
            }
          } catch (e) {
            print('Error fetching serial for update: $e');
            throw Exception('Failed to get new serial for updated item: $e');
          }
        } else {
          print('Using existing serial for updated item: $serial');
        }

        print('Full data of sending buy item: $buyItem');

        final buyData = {...buyItem, 'BillId': billId};
        final query = _buildBuysInsertQuery(buyData);

        print('Insert query for buy item: $query');

        try {
          await _remote.writeData(query);
        } catch (writeError) {
          print('Error writing buy item to database: $writeError');
        }

        // Update local with new serial and type
        await _local.updateBuySerial(
          billId,
          item['ItemId'] as int,
          serial,
          'Automatic',
        );
      }
    } catch (e) {
      print('Error in updateBuysBillOnServer: $e');
      rethrow;
    }
  }

  String _buildBuysBillInsertQuery(Map<String, dynamic> bill, String billNum) {
    final theDate = bill['TheDate'] ?? '';
    final sellerId = bill['SellerId'] ?? 'NULL';
    final branchId = bill['BranchId'] ?? 'NULL';
    final userId = bill['UserId'] ?? 'NULL';
    final total = bill['Total'] ?? 'NULL';
    final paied = bill['Paied'] ?? 'NULL';

    final lock = bill['Lock'] != null
        ? "N'${_escapeSqlString(bill['Lock'].toString())}'"
        : 'NULL';

    final pastAccount = bill['PastAccount'] ?? 'NULL';
    final netTotal = bill['NetTotal'] ?? 'NULL';
    final discount = bill['Discount'] ?? 'NULL';
    final rest = bill['Rest'] ?? 'NULL';
    final grandTotal = bill['GrandTotal'] ?? 'NULL';
    final type = bill['Type'] != null
        ? "N'${_escapeSqlString(bill['Type'].toString())}'"
        : "N'شراء'";

    return '''
DECLARE @Inserted TABLE (Id INT);

INSERT INTO [BuysBills] (
    TheDate,
    Bill,
    SellerId,
    BranchId,
    UserId,
    Total,
    Paied,         
    Lock,
    PastAccount,
    NetTotal,
    Discount,
    Rest,          
    GrandTotal,
    Type  
)
OUTPUT INSERTED.Id INTO @Inserted(Id)
VALUES (
    CONVERT(datetime, '$theDate', 120),
    '$billNum',
    $sellerId,
    $branchId,
    $userId,
    $total,
    $paied,       
    $lock,
    $pastAccount,
    $netTotal,
    $discount,
    $rest,         
    $grandTotal,
    $type 
);

SELECT Id FROM @Inserted;
''';
  }

  String _buildBuysInsertQuery(Map<String, dynamic> buy) {
    final billId = buy['BillId'] ?? 'NULL';
    final itemId = buy['ItemId'] ?? 'NULL';
    final qty = buy['Qty'] ?? 'NULL';
    final price = buy['Price'] ?? 'NULL';
    final total = buy['Total'] ?? 'NULL';
    final serial = buy['Serial']?.toString() ?? '';

    final qtyUnit = buy['QtyUnit'] != null
        ? "N'${_escapeSqlString(buy['QtyUnit'].toString())}'"
        : 'NULL';
    final type = buy['Type'] != null
        ? "N'${_escapeSqlString(buy['Type'].toString())}'"
        : "N'شراء'";
    final firstPrice = buy['FirstPrice'] ?? price;
    final unitQty = buy['UnitQty'] ?? 'NULL';
    final totalQty = buy['TotalQty'] ?? 'NULL';
    final serialValue = serial.isNotEmpty ? _escapeSqlString(serial) : 'NULL';
    final serialType = "N'Automatic'";

    // IMPORTANT: Remove any OUTPUT clause since writeData() can't handle result sets
    return '''
    INSERT INTO [Buys] (BillId, ItemId, Qty, Price, Total, QtyUnit, Type, FirstPrice, UnitQty, TotalQty, Serial, SerialType)
    VALUES ($billId, $itemId, $qty, $price, $total, $qtyUnit, $type, $firstPrice, $unitQty, $totalQty, $serialValue, $serialType);
  ''';
  }

  //! CODING CLIENTS, SELLERS, ITEMS

  Future<int> _getMaxClientId() async {
    final query = "SELECT MAX(ClientId) AS MaxId FROM [Clients]";
    final result = await _remote.getData(query);
    final rows = result['rows'] as List<dynamic>? ?? [];
    if (rows.isNotEmpty) {
      return (rows.first['MaxId'] as int?) ?? 0;
    }
    return 0;
  }

  Future<void> addNewClient({
    int? clientId,
    required String client,
    required String address,
    required String phone,
    required double start,
    int? regionId,
  }) async {
    try {
      await _ensureConnection();

      final insertId = clientId ?? (await _getMaxClientId()) + 1;

      final query =
          '''
      INSERT INTO [Clients] (
        ClientId,
        Client,
        Address,
        Phone,
        Start,
        RegionId
      ) VALUES (
        $insertId,
        N'${_escapeSqlString(client)}',
        N'${_escapeSqlString(address)}',
        N'${_escapeSqlString(phone)}',
        $start,
        ${regionId ?? 'NULL'}
      );
      ''';

      await _remote.writeData(query);

      // Sync the updated clients table to local
      await _fetchTableFromServer('Clients', tableColumns['Clients']!);
    } catch (e) {
      rethrow;
    }
  }

  Future<int> _getMaxSellerId() async {
    final query = "SELECT MAX(SellerId) AS MaxId FROM [Sellers]";
    final result = await _remote.getData(query);
    final rows = result['rows'] as List<dynamic>? ?? [];
    if (rows.isNotEmpty) {
      return (rows.first['MaxId'] as int?) ?? 0;
    }
    return 0;
  }

  Future<void> addNewSeller({
    int? sellerId,
    required String seller,
    required String address,
    required String phone,
    required double start,
  }) async {
    try {
      await _ensureConnection();

      final insertId = sellerId ?? (await _getMaxSellerId()) + 1;

      final query =
          '''
      INSERT INTO [Sellers] (
        SellerId,
        Seller,
        Address,
        Phone,
        Start
      ) VALUES (
        $insertId,
        N'${_escapeSqlString(seller)}',
        N'${_escapeSqlString(address)}',
        N'${_escapeSqlString(phone)}',
        $start
      );
      ''';

      await _remote.writeData(query);

      // Sync the updated sellers table to local
      await _fetchTableFromServer('Sellers', tableColumns['Sellers']!);
    } catch (e) {
      rethrow;
    }
  }

  Future<int> _getNewItemId() async {
    // Assuming GetNewItem is a table with a column NewItemId
    final query = "SELECT NewItemId FROM GetNewItem";
    final result = await _remote.getData(query);
    final rows = result['rows'] as List<dynamic>? ?? [];

    if (rows.isNotEmpty) {
      return (rows.first['NewItemId'] as int?) ?? 0;
    }
    return 0;
  }

  Future<void> addNewItem({
    int? itemId, // Reverted to int as requested
    required String name,
    required int categoryId,
    required double buyPrice,
    required double sellingPrice,
    required double unitQty,
  }) async {
    try {
      await _ensureConnection();

      //  If itemId is provided, use it. Otherwise, fetch from GetNewItem and increment by 1.
      final int rawId = itemId ?? (await _getNewItemId()) + 1;

      // Convert the final integer to a String for the database insert
      final String stringId = rawId.toString();
      final query =
          '''
      INSERT INTO [STRItems] (
        ItemId,
        Name,
        CategoryId,
        BuyPrice,
        SellingPrice,
        UnitQty
      ) VALUES (
        '$stringId', -- Inserted as a string with single quotes
        N'${_escapeSqlString(name)}',
        $categoryId,
        $buyPrice,
        $sellingPrice,
        $unitQty
      );
      ''';

      await _remote.writeData(query);

      // Sync the updated items table to local
      await _fetchTableFromServer('STRItems', tableColumns['STRItems']!);
    } catch (e) {
      print("Error in adding new item: $e");
      rethrow;
    }
  }

  //! RESULT AND CONNECTION

  bool _isSuccessResult(Map<String, dynamic> result) {
    return !result.containsKey('ErrorNumber') &&
        !result.containsKey('ErrorMessage');
  }

  Future<void> _ensureConnection() async {
    try {
      if (!_remote.isConnected) {
        final connected = await _remote.reconnect();
        if (!connected) {
          throw Exception('Failed to connect to server');
        }
      }
    } catch (e) {
      throw Exception('Server connection failed: $e');
    }
  }

  // Public methods for connection management
  Future<bool> checkConnection() async {
    try {
      return await _remote.reconnect();
    } catch (e) {
      return false;
    }
  }

  bool get isConnected => _remote.isConnected;

  Future<void> disconnect() async {
    try {
      await _remote.disconnect();
    } catch (e) {}
  }
}
