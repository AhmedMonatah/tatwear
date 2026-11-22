import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class LocalDbService {
  LocalDbService._internal();
  static final LocalDbService instance = LocalDbService._internal();

  Database? _db;

  Future<Database> get db async => _db ??= await _init();

  Future<void> init() async {
    _db ??= await _init();
  }

  Future<Database> _init() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'tatweer_local.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE Sells ADD COLUMN ItemBranchId INTEGER');
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await _createReadOnlyTables(db);
    await _createWriteTables(db);
  }

  Future<void> _createReadOnlyTables(Database db) async {
    await db.execute(
      'CREATE TABLE Region (RegionId INTEGER PRIMARY KEY, Region TEXT);',
    );
    await db.execute('''
      CREATE TABLE Clients (
        Id INTEGER PRIMARY KEY, Client TEXT, Phone TEXT, Address TEXT, RegionId INTEGER
      );
    ''');
    await db.execute('''
      CREATE TABLE Sellers (
        Id INTEGER PRIMARY KEY, Seller TEXT, Phone TEXT, Address TEXT);
    ''');
    await db.execute(
      'CREATE TABLE STRCategory (Id INTEGER PRIMARY KEY, Category TEXT);',
    );
    await db.execute('''
      CREATE TABLE STRItems (
        Id INTEGER PRIMARY KEY, ItemId INTEGER, Name TEXT, CategoryId INTEGER,
        SellingPrice REAL, SellingPriceBig REAL, WholesalePrice REAL, WholesalePriceBig REAL,BuyPrice Real, BuyPriceBig Real, UnitQty REAL
      );
    ''');
    await db.execute('''
      CREATE TABLE vw_Inventory_AllBranches_Current (
        Id INTEGER PRIMARY KEY, Name TEXT, ItemId INTEGER, BranchName TEXT, BranchId INTEGER, Qty REAL, CategoryId INTEGER,
        SellingPrice REAL, SellingPriceBig REAL, WholesalePrice REAL, WholesalePriceBig REAL, BuyPrice REAL, BuyPriceBig Real, UnitQty REAL
      );
    ''');
    await db.execute('''
      CREATE TABLE ClientBranchs (Id INTEGER PRIMARY KEY, ClientId INTEGER, BranchId INTEGER);
    ''');
    await db.execute('''
      CREATE TABLE Settings (
        Id INTEGER PRIMARY KEY, Company TEXT, Address TEXT, Phones TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE Branchs (
        Id INTEGER PRIMARY KEY, Name TEXT
      );
    ''');
  }

  Future<void> _createWriteTables(Database db) async {
    await db.execute('''
      CREATE TABLE SellsBills (
        Id INTEGER PRIMARY KEY, Bill TEXT, TheDate TEXT, ClientId INTEGER,
        BranchId INTEGER, UserId INTEGER, Total REAL, PaiedForien REAL, Lock TEXT,PastAccount 
        REAL, NetTotal REAL , Discount REAL , Rest REAL , GrandTotal Real, Settlement TEXT,
        LocalUuid TEXT, Synced INTEGER DEFAULT 1
      );
    ''');
    await db.execute('''
  CREATE TABLE Sells (
    RowId INTEGER PRIMARY KEY AUTOINCREMENT, BillId INTEGER, ItemId INTEGER,
    Qty REAL, Price REAL, Total REAL, QtyUnit TEXT, Pricing TEXT, Type TEXT, FirstPrice REAL, BuyPrice REAL,
    UnitQty REAL, TotalQty REAL, ItemBranchId INTEGER, LocalUuid TEXT, Synced INTEGER DEFAULT 1
  );
''');
    await db.execute('''
  CREATE TABLE ClientsPaying (
    Id INTEGER PRIMARY KEY, ClientId INTEGER, TheDate TEXT, Bill TEXT, 
    Amount REAL, BranchId INTEGER, UserId INTEGER, Notes TEXT,
    LocalUuid TEXT, Synced INTEGER DEFAULT 1, Lock TEXT
  );
''');
    await db.execute('''
  CREATE TABLE BuysBills (
  Id INTEGER PRIMARY KEY, Bill TEXT, TheDate TEXT, SellerId INTEGER,
  BranchId INTEGER, UserId INTEGER, Total REAL, Paied REAL, Lock TEXT, PastAccount REAL, 
  NetTotal REAL, Discount REAL, Rest REAL, GrandTotal REAL, Type TEXT,
  LocalUuid TEXT, Synced INTEGER DEFAULT 1
);
''');
    await db.execute('''
  CREATE TABLE Buys (
    RowId INTEGER PRIMARY KEY AUTOINCREMENT, BillId INTEGER, ItemId INTEGER,
    Qty REAL, Price REAL, Total REAL, QtyUnit TEXT, Type TEXT, FirstPrice REAL,
    UnitQty REAL, TotalQty REAL, Serial TEXT, SerialType TEXT, LocalUuid TEXT, Synced INTEGER DEFAULT 1
  );
''');
    await db.execute('''
      CREATE TABLE ExchangeBills (
        Id INTEGER PRIMARY KEY,
        Bill TEXT,
        TheDate TEXT,
        UserId INTEGER,
        Total REAL,
        Lock TEXT,
        BranchId INTEGER,
        DestBranchId INTEGER,
        LocalUuid TEXT,
        Synced INTEGER DEFAULT 1
      );
    ''');

    await db.execute('''
      CREATE TABLE Exchange (
        RowId INTEGER PRIMARY KEY AUTOINCREMENT,
        BillId INTEGER,
        Qty REAL,
        QtyUnit TEXT,
        Price REAL,
        Total REAL,
        ItemId INTEGER,
        UnitQty REAL,
        TotalQty REAL,
        BranchId INTEGER,
        DestBranchId INTEGER,
        LocalUuid TEXT,
        Synced INTEGER DEFAULT 1
      );
    ''');
  }

  // clears all data from all tables AND resets auto-increment IDs
  Future<void> clearAllTables() async {
    final database = await db;

    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
    );

    final batch = database.batch();

    for (final table in tables) {
      final tableName = table['name'] as String;

      // delete all rows
      batch.delete(tableName);

      // reset auto-increment counter
      batch.execute("DELETE FROM sqlite_sequence WHERE name = '$tableName'");
    }

    await batch.commit(noResult: true);
  }

  Future<void> upsertTableWithColumns(
    String table,
    List<String> columns,
    List<dynamic> rows,
  ) async {
    final database = await db;
    final batch = database.batch();
    await database.delete(table);

    for (final row in rows) {
      if (row is Map) {
        final data = <String, dynamic>{};
        for (final column in columns) {
          data[column] = _findValue(row, column);
        }
        batch.insert(table, data);
      }
    }
    await batch.commit(noResult: true);
  }

  dynamic _findValue(Map row, String column) {
    if (row.containsKey(column)) return row[column];
    if (row.containsKey(column.toLowerCase())) return row[column.toLowerCase()];
    return row[column.toUpperCase()];
  }

  // NEW: Method to get settings
  Future<List<Map<String, dynamic>>> getSettings() async {
    final database = await db;
    return database.query('Settings');
  }

  Future<List<Map<String, dynamic>>> getClients() async {
    final database = await db;
    return database.query('Clients');
  }

  //  Get sellers
  Future<List<Map<String, dynamic>>> getSellers() async {
    final database = await db;
    return database.query('Sellers');
  }

  Future<List<Map<String, dynamic>>> readTable(String table) async {
    final database = await db;
    return database.query(table);
  }

  Future<List<Map<String, dynamic>>> getPendingSellsBills() async {
    final database = await db;

    // Get the current user ID from shared preferences
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    // If userId is null, return an empty list or handle accordingly
    if (userId == null) {
      return [];
    }

    // Query only bills that are not synced AND belong to this user
    return database.query(
      'SellsBills',
      where: 'Synced = ? AND UserId = ?',
      whereArgs: [0, userId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingSells() async {
    final database = await db;
    return database.query('Sells', where: 'Synced = ?', whereArgs: [0]);
  }

  Future<List<Map<String, dynamic>>> getUserSellsBills(int userId) async {
    final database = await db;
    return database.query(
      'SellsBills',
      where: 'UserId = ?',
      whereArgs: [userId],
      orderBy: 'TheDate DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getSellItemsByBillId(int billId) async {
    final database = await db;

    final result = await database.query(
      'Sells',
      where: 'BillId = ?',
      whereArgs: [billId],
    );

    return result;
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final database = await db;
    return database.query('STRCategory', orderBy: 'Category ASC');
  }

  Future<List<Map<String, dynamic>>> getItemsByCategory(
    int? categoryId, {
    String searchTerm = '',
  }) async {
    final database = await db;
    final where = <String>[];
    final args = <Object?>[];
    if (categoryId != null) {
      where.add('CategoryId = ?');
      args.add(categoryId);
    }
    if (searchTerm.isNotEmpty) {
      where.add('Name LIKE ?');
      args.add('%$searchTerm%');
    }
    return database.query(
      'STRItems',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'Name ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getInventoryItemsByCategory(
    int? categoryId, {
    String searchTerm = '',
  }) async {
    final database = await db;
    final where = <String>[];
    final args = <Object?>[];
    if (categoryId != null) {
      where.add('CategoryId = ?');
      args.add(categoryId);
    }
    if (searchTerm.isNotEmpty) {
      where.add('Name LIKE ?');
      args.add('%$searchTerm%');
    }
    return database.query(
      'vw_Inventory_AllBranches_Current',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'Name ASC',
    );
  }

  Future<double?> getItemPrice(int itemId, String pricing, String unit) async {
    final database = await db;
    final result = await database.query(
      'STRItems',
      where: 'Id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final row = result.first;
    final isRetail = pricing == 'تجزئة';
    final isSmall = unit == 'صغرى';
    final column = isRetail
        ? (isSmall ? 'SellingPrice' : 'SellingPriceBig')
        : (isSmall ? 'WholesalePrice' : 'WholesalePriceBig');
    final value = row[column];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<double?> getInventoryItemPrice(
    int itemId,
    String pricing,
    String unit, {
    required bool
    isSelling, //  true = use selling prices, false = use buying prices (BuyPrice / BuyPriceBig)
  }) async {
    final database = await db;

    final result = await database.query(
      'vw_Inventory_AllBranches_Current',
      where: 'Id = ?',
      whereArgs: [itemId],
      limit: 1,
    );

    if (result.isEmpty) return null;

    final row = result.first;

    final isRetail = pricing == 'تجزئة';
    final isSmall = unit == 'صغرى';

    String column;

    if (isSelling) {
      //  Selling logic (current behavior)
      column = isRetail
          ? (isSmall ? 'SellingPrice' : 'SellingPriceBig')
          : (isSmall ? 'WholesalePrice' : 'WholesalePriceBig');
    } else {
      // Buying logic (no wholesale, only BuyPrice fields)
      column = isSmall ? 'BuyPrice' : 'BuyPriceBig';
    }

    final value = row[column];

    if (value == null) return null;
    if (value is num) return value.toDouble();

    return double.tryParse(value.toString());
  }

  Future<String?> getClientName(int clientId) async {
    final database = await db;
    final result = await database.query(
      'Clients',
      columns: ['Client'],
      where: 'Id = ?',
      whereArgs: [clientId],
    );
    return result.isNotEmpty ? result.first['Client'] as String? : null;
  }

  Future<Map<String, dynamic>?> getClientById(int clientId) async {
    final database = await db;
    final result = await database.query(
      'Clients',
      where: 'Id = ?',
      whereArgs: [clientId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<String?> getSellerName(int sellerId) async {
    final database = await db;
    final result = await database.query(
      'Sellers',
      columns: ['Seller'],
      where: 'Id = ?',
      whereArgs: [sellerId],
    );
    return result.isNotEmpty ? result.first['Seller'] as String? : null;
  }

  Future<Map<String, dynamic>?> getSellerById(int sellerId) async {
    final database = await db;
    final result = await database.query(
      'Sellers',
      where: 'Id = ?',
      whereArgs: [sellerId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getRegionById(int regionId) async {
    final database = await db;
    final result = await database.query(
      'Region',
      where: 'RegionId = ?',
      whereArgs: [regionId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getSTRItemById(int itemId) async {
    final database = await db;
    final result = await database.query(
      'STRItems',
      where: 'Id = ?',
      whereArgs: [itemId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getInventoryItemById(int itemId) async {
    final database = await db;
    final result = await database.query(
      'vw_Inventory_AllBranches_Current',
      where: 'Id = ?',
      whereArgs: [itemId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Get all branches from the Branchs table.
  Future<List<Map<String, dynamic>>> getBranches() async {
    final database = await db;
    return database.query('Branchs', orderBy: 'Name ASC');
  }

  /// Get a single branch by its ID.
  Future<Map<String, dynamic>?> getBranchById(int? branchId) async {
    if (branchId == null) return null;
    final database = await db;
    final result = await database.query(
      'Branchs',
      where: 'Id = ?',
      whereArgs: [branchId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  // WRITE Operations

  //! SELLS AND SELLS BILLS OPERATIONS
  Future<void> storeSellsBills(List<Map<String, dynamic>> bills) async {
    final database = await db;
    final batch = database.batch();

    for (final bill in bills) {
      batch.insert('SellsBills', {
        ...bill,
        'Synced': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> storeSellsItems(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;

    final database = await db;
    final batch = database.batch();

    // Extract unique BillIds from the incoming list
    final billIds = items.map((e) => e['BillId']).toSet();

    // Step 1: Delete all existing rows with these BillIds
    for (final billId in billIds) {
      if (billId != null) {
        batch.delete('Sells', where: 'BillId = ?', whereArgs: [billId]);
      }
    }

    // Step 2: Insert new rows with all columns
    for (final item in items) {
      final sellData = {
        'BillId': item['BillId'],
        'ItemId': item['ItemId'],
        'Qty': item['Qty'],
        'Price': item['Price'],
        'Total': item['Total'],
        'QtyUnit': item['QtyUnit'],
        'Pricing': item['Pricing'],
        'Type': item['Type'] ?? 'بيع',
        'FirstPrice': item['FirstPrice'] ?? item['Price'],
        'BuyPrice': item['BuyPrice'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'] ?? item['Qty'],
        'ItemBranchId': item['ItemBranchId'],
        'Synced': 1,
      };

      batch.insert(
        'Sells',
        sellData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertSellsBill(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
      'SellsBills',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertSells(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
      'Sells',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // === Added helpers for bill/item creation and post-sync mapping ===
  Future<void> batchInsertSells(
    List<Map<String, dynamic>> items,
    int billId, {
    String? localUuid,
  }) async {
    if (items.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final item in items) {
      final data = {
        'BillId': billId,
        'ItemId': item['ItemId'],
        'Qty': item['Qty'],
        'Price': item['Price'],
        'Total': item['Total'],
        'QtyUnit': item['QtyUnit'],
        'Pricing': item['Pricing'],
        'Type': item['Type'] ?? 'بيع',
        'FirstPrice': item['FirstPrice'] ?? item['Price'],
        'BuyPrice': item['BuyPrice'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'] ?? item['Qty'],
        'ItemBranchId': item['ItemBranchId'],
        'LocalUuid': localUuid,
        'Synced': 0,
      };
      batch.insert('Sells', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceSellsItems(
    int billId,
    List<Map<String, dynamic>> items,
  ) async {
    final database = await db;
    final batch = database.batch();

    // Delete existing items for this bill
    batch.delete('Sells', where: 'BillId = ?', whereArgs: [billId]);

    // Insert new items with actual values
    for (final item in items) {
      final data = {
        'BillId': billId,
        'ItemId': item['ItemId'],
        'Qty': item['Qty'],
        'Price': item['Price'],
        'Total': item['Total'],
        'QtyUnit': item['QtyUnit'],
        'Pricing': item['Pricing'],
        'Type': item['Type'] ?? 'بيع',
        'FirstPrice': item['FirstPrice'] ?? item['Price'],
        'BuyPrice': item['BuyPrice'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'],
        'ItemBranchId': item['ItemBranchId'],
        'Synced': 0,
      };
      batch.insert('Sells', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<void> markBillAsPendingSync(int billId) async {
    final database = await db;
    await database.update(
      'SellsBills',
      {'Synced': 0},
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  Future<void> markBillAsSynced(int billId) async {
    final database = await db;
    await database.update(
      'SellsBills',
      {'Synced': 1},
      where: 'Id = ?',
      whereArgs: [billId],
    );

    // Also mark all sells items as synced
    await database.update(
      'Sells',
      {'Synced': 1},
      where: 'BillId = ?',
      whereArgs: [billId],
    );
  }

  // Update bill total and lock status
  Future<void> updateBillTotalPaiedAndLock(
    int billId,
    double total,
    double paied,
    String? lock, {
    double discount = 0.0,
    double pastAccount = 0.0,
    double netTotal = 0.0,
    double grandTotal = 0.0,
    double rest = 0.0,
    String settlement = 'آجل',
  }) async {
    final database = await db;
    await database.update(
      'SellsBills',
      {
        'Total': total,
        'PaiedForien': paied,
        'Lock': lock,
        'Discount': discount,
        'PastAccount': pastAccount,
        'NetTotal': netTotal,
        'GrandTotal': grandTotal,
        'Rest': rest,
        'Settlement': settlement,
        'Synced': 0,
      },
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  // Update only lock status
  Future<void> updateBillLockStatus(int billId, String? lock) async {
    final database = await db;
    await database.update(
      'SellsBills',
      {
        'Lock': lock,
        'Synced': 0, // Mark as not synced when lock changes
      },
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingUpdatedBills() async {
    final database = await db;
    return database.query(
      'SellsBills',
      where: 'Synced = ? AND Bill IS NOT NULL',
      whereArgs: [0],
    );
  }

  Future<Map<String, dynamic>> createLocalBill({
    required DateTime theDate,
    required int clientId,
    required int branchId,
    required int userId,
    double total = 0.0,
    double paied = 0.0,
    String? localUuid,
    String? lock,
    double pastAccount = 0.0,
    double netTotal = 0.0,
    double discount = 0.0,
    double rest = 0.0,
    double grandTotal = 0.0,
    String settlement = 'آجل',
  }) async {
    final database = await db;
    final uuid = localUuid ?? DateTime.now().microsecondsSinceEpoch.toString();
    final formattedDate =
        '${theDate.year}-${theDate.month.toString().padLeft(2, '0')}-${theDate.day.toString().padLeft(2, '0')} ${theDate.hour.toString().padLeft(2, '0')}:${theDate.minute.toString().padLeft(2, '0')}:${theDate.second.toString().padLeft(2, '0')}';
    final data = {
      'Bill': null,
      'TheDate': formattedDate,
      'ClientId': clientId,
      'BranchId': branchId,
      'UserId': userId,
      'Total': total,
      'PaiedForien': paied,
      'LocalUuid': uuid,
      'Synced': 0,
      'Lock': lock,
      'PastAccount': pastAccount,
      'NetTotal': netTotal,
      'Discount': discount,
      'Rest': rest,
      'GrandTotal': grandTotal,
      'Settlement': settlement,
    };
    final id = await database.insert(
      'SellsBills',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return {'Id': id, 'LocalUuid': uuid};
  }

  // Updated updateBillIdAndNumberByLocalUuid in LocalDbService
  Future<void> updateBillIdAndNumberByLocalUuid(
    String localUuid,
    int newId,
    String newBill,
  ) async {
    final database = await db;
    // Get the existing row to know previous Id
    final rows = await database.query(
      'SellsBills',
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
      limit: 1,
    );
    int? oldId = rows.isNotEmpty ? rows.first['Id'] as int? : null;

    // Update bill with server values
    await database.update(
      'SellsBills',
      {'Id': newId, 'Bill': newBill, 'Synced': 1},
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
    );

    // Update sells rows by LocalUuid first (update BillId only, leave Synced=0)
    await database.update(
      'Sells',
      {'BillId': newId},
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
    );

    // If any rows still reference the old local Id, fix them (update BillId only, leave Synced=0)
    if (oldId != null) {
      await database.update(
        'Sells',
        {'BillId': newId},
        where: 'BillId = ?',
        whereArgs: [oldId],
      );
    }
  }

  Future<void> markSellsBillSynced(String bill) async {
    if (bill.isEmpty) return;
    final database = await db;
    await database.update(
      'SellsBills',
      {'Synced': 1},
      where: 'Bill = ?',
      whereArgs: [bill],
    );
  }

  Future<void> markSellsSynced(int billId) async {
    final database = await db;
    await database.update(
      'Sells',
      {'Synced': 1},
      where: 'BillId = ?',
      whereArgs: [billId],
    );
  }

  //! Buys METHODS - UPDATED FOR CONSISTENCY WITH BILLS
  Future<void> storeBuysBills(List<Map<String, dynamic>> bills) async {
    final database = await db;
    final batch = database.batch();

    for (final bill in bills) {
      batch.insert('BuysBills', {
        ...bill,
        'Synced': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> storeBuysItems(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;

    final database = await db;
    final batch = database.batch();

    final billIds = items.map((e) => e['BillId']).toSet();

    for (final billId in billIds) {
      if (billId != null) {
        batch.delete('Buys', where: 'BillId = ?', whereArgs: [billId]);
      }
    }

    for (final item in items) {
      final buyData = {
        'BillId': item['BillId'],
        'ItemId': item['ItemId'],
        'Qty': item['Qty'],
        'Price': item['Price'],
        'Total': item['Total'],
        'QtyUnit': item['QtyUnit'],
        'Type': item['Type'] ?? 'شراء',
        'FirstPrice': item['FirstPrice'] ?? item['Price'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'] ?? item['Qty'],
        'Serial': item['Serial']?.toString(),
        'SerialType': item['SerialType']?.toString(),
        'Synced': 1,
      };

      batch.insert(
        'Buys',
        buyData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getPendingBuysBills() async {
    final database = await db;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null) {
      return [];
    }

    return database.query(
      'BuysBills',
      where: 'Synced = ? AND UserId = ?',
      whereArgs: [0, userId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingBuys() async {
    final database = await db;
    return database.query('Buys', where: 'Synced = ?', whereArgs: [0]);
  }

  Future<List<Map<String, dynamic>>> getUserBuysBills(int userId) async {
    final database = await db;

    return database.query(
      'BuysBills',
      where: 'UserId = ?',
      whereArgs: [userId],
      orderBy: 'TheDate DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getBuysItemsByBillId(int billId) async {
    final database = await db;
    return database.query('Buys', where: 'BillId = ?', whereArgs: [billId]);
  }

  Future<List<Map<String, dynamic>>> getBuysItemsByLocalUuid(
    String localUuid,
  ) async {
    final database = await db;
    return database.query(
      'Buys',
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
    );
  }

  Future<void> insertBuysBill(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
      'BuysBills',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertBuys(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
      'Buys',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> batchInsertBuys(
    List<Map<String, dynamic>> items,
    int billId, {
    String? localUuid,
  }) async {
    if (items.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final item in items) {
      final data = {
        'BillId': billId,
        'ItemId': item['ItemId'],
        'Qty': item['Qty'],
        'Price': item['Price'],
        'Total': item['Total'],
        'QtyUnit': item['QtyUnit'],
        'Type': item['Type'] ?? 'شراء',
        'FirstPrice': item['FirstPrice'] ?? item['Price'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'] ?? item['Qty'],
        'Serial': item['Serial']?.toString(),
        'SerialType': item['SerialType'] ?? 'Automatic',
        'LocalUuid': localUuid,
        'Synced': 0,
      };
      batch.insert('Buys', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceBuysItems(
    int billId,
    List<Map<String, dynamic>> items,
  ) async {
    final database = await db;
    final batch = database.batch();

    batch.delete('Buys', where: 'BillId = ?', whereArgs: [billId]);

    for (final item in items) {
      final data = {
        'BillId': billId,
        'ItemId': item['ItemId'],
        'Qty': item['Qty'],
        'Price': item['Price'],
        'Total': item['Total'],
        'QtyUnit': item['QtyUnit'],
        'Type': item['Type'] ?? 'شراء',
        'FirstPrice': item['FirstPrice'] ?? item['Price'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'],
        'Serial': item['Serial']?.toString(),
        'SerialType': item['SerialType'] ?? 'Automatic',
        'Synced': 0,
      };
      batch.insert('Buys', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>> createLocalBuysBill({
    required DateTime theDate,
    required int sellerId,
    required int branchId,
    required int userId,
    double total = 0.0,
    double paied = 0.0,
    String? localUuid,
    String? lock,
    double pastAccount = 0.0,
    double netTotal = 0.0,
    double discount = 0.0,
    double rest = 0.0,
    double grandTotal = 0.0,
    String type = 'شراء',
  }) async {
    final database = await db;
    final uuid = localUuid ?? DateTime.now().microsecondsSinceEpoch.toString();
    final formattedDate =
        '${theDate.year}-${theDate.month.toString().padLeft(2, '0')}-${theDate.day.toString().padLeft(2, '0')} ${theDate.hour.toString().padLeft(2, '0')}:${theDate.minute.toString().padLeft(2, '0')}:${theDate.second.toString().padLeft(2, '0')}';
    final data = {
      'Bill': null,
      'TheDate': formattedDate,
      'SellerId': sellerId,
      'BranchId': branchId,
      'UserId': userId,
      'Total': total,
      'Paied': paied,
      'LocalUuid': uuid,
      'Synced': 0,
      'Lock': lock,
      'PastAccount': pastAccount,
      'NetTotal': netTotal,
      'Discount': discount,
      'Rest': rest,
      'GrandTotal': grandTotal,
      'Type': type,
    };
    final id = await database.insert(
      'BuysBills',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return {'Id': id, 'LocalUuid': uuid};
  }

  Future<void> updateBuysBillTotalAndLock(
    int billId,
    double total, {
    double paied = 0.0,
    String? lock,
    double discount = 0.0,
    double pastAccount = 0.0,
    double netTotal = 0.0,
    double rest = 0.0,
    double grandTotal = 0.0,
    String type = 'شراء',
  }) async {
    final database = await db;
    await database.update(
      'BuysBills',
      {
        'Total': total,
        'Paied': paied,
        'Lock': lock,
        'Discount': discount,
        'PastAccount': pastAccount,
        'NetTotal': netTotal,
        'Rest': rest,
        'GrandTotal': grandTotal,
        'Type': type,
        'Synced': 0,
      },
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  Future<void> markBuysBillAsPendingSync(int billId) async {
    final database = await db;
    await database.update(
      'BuysBills',
      {'Synced': 0},
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  Future<void> markBuysBillAsSynced(int billId) async {
    final database = await db;
    await database.update(
      'BuysBills',
      {'Synced': 1},
      where: 'Id = ?',
      whereArgs: [billId],
    );

    await database.update(
      'Buys',
      {'Synced': 1},
      where: 'BillId = ?',
      whereArgs: [billId],
    );
  }

  Future<void> updateBuysBillLockStatus(int billId, String? lock) async {
    final database = await db;
    await database.update(
      'BuysBills',
      {'Lock': lock, 'Synced': 0},
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingUpdatedBuysBills() async {
    final database = await db;
    return database.query(
      'BuysBills',
      where: 'Synced = ? AND Bill IS NOT NULL',
      whereArgs: [0],
    );
  }

  Future<void> updateBuysBillIdAndNumberByLocalUuid(
    String localUuid,
    int newId,
    String newBill,
  ) async {
    final database = await db;
    final rows = await database.query(
      'BuysBills',
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
      limit: 1,
    );
    int? oldId = rows.isNotEmpty ? rows.first['Id'] as int? : null;

    // Update bill with server values (Serial removed)
    await database.update(
      'BuysBills',
      {'Id': newId, 'Bill': newBill, 'Synced': 1},
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
    );

    await database.update(
      'Buys',
      {'BillId': newId},
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
    );

    if (oldId != null) {
      await database.update(
        'Buys',
        {'BillId': newId},
        where: 'BillId = ?',
        whereArgs: [oldId],
      );
    }
  }

  Future<void> markBuysBillSynced(String bill) async {
    if (bill.isEmpty) return;
    final database = await db;
    await database.update(
      'BuysBills',
      {'Synced': 1},
      where: 'Bill = ?',
      whereArgs: [bill],
    );
  }

  Future<void> markBuysSynced(int billId) async {
    final database = await db;
    await database.update(
      'Buys',
      {'Synced': 1},
      where: 'BillId = ?',
      whereArgs: [billId],
    );
  }

  Future<void> updateBuySerial(
    int billId,
    int itemId,
    String serial,
    String serialType,
  ) async {
    final database = await db;
    await database.update(
      'Buys',
      {'Serial': serial, 'SerialType': serialType},
      where: 'BillId = ? AND ItemId = ?',
      whereArgs: [billId, itemId],
    );
  }

  //! COLLECTION METHODS - UPDATED FOR CONSISTENCY WITH BILLS
  Future<void> insertCollection(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
      'ClientsPaying',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Updated createLocalCollection method with Lock field
  Future<Map<String, dynamic>> createLocalCollection({
    required DateTime theDate,
    required int clientId,
    required String bill,
    required double amount,
    required int branchId,
    required int userId,
    String? notes,
    String? localUuid,
    String? lock,
  }) async {
    final database = await db;
    final uuid = localUuid ?? DateTime.now().microsecondsSinceEpoch.toString();
    final formattedDate =
        '${theDate.year}-${theDate.month.toString().padLeft(2, '0')}-${theDate.day.toString().padLeft(2, '0')} ${theDate.hour.toString().padLeft(2, '0')}:${theDate.minute.toString().padLeft(2, '0')}:${theDate.second.toString().padLeft(2, '0')}';

    final data = {
      'ClientId': clientId,
      'TheDate': formattedDate,
      'Bill': bill,
      'Amount': amount,
      'BranchId': branchId,
      'UserId': userId,
      'Notes': notes,
      'LocalUuid': uuid,
      'Synced': 0,
      'Lock': lock,
    };

    final id = await database.insert(
      'ClientsPaying',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return {'Id': id, 'LocalUuid': uuid};
  }

  // NEW: Method to create local collection without bill number (for new collections)
  Future<Map<String, dynamic>> createNewLocalCollection({
    required DateTime theDate,
    required int clientId,
    required double amount,
    required int branchId,
    required int userId,
    String? notes,
    String? localUuid,
    String? lock,
  }) async {
    final database = await db;
    final uuid = localUuid ?? DateTime.now().microsecondsSinceEpoch.toString();
    final formattedDate =
        '${theDate.year}-${theDate.month.toString().padLeft(2, '0')}-${theDate.day.toString().padLeft(2, '0')} ${theDate.hour.toString().padLeft(2, '0')}:${theDate.minute.toString().padLeft(2, '0')}:${theDate.second.toString().padLeft(2, '0')}';

    final data = {
      'ClientId': clientId,
      'TheDate': formattedDate,
      'Bill': null, // Bill will be assigned during sync
      'Amount': amount,
      'BranchId': branchId,
      'UserId': userId,
      'Notes': notes,
      'LocalUuid': uuid,
      'Synced': 0,
      'Lock': lock,
    };

    final id = await database.insert(
      'ClientsPaying',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return {'Id': id, 'LocalUuid': uuid};
  }

  // Updated updateCollection method
  Future<void> updateCollection(
    int collectionId,
    double amount,
    String notes, {
    String? lock,
  }) async {
    final database = await db;
    final updateData = <String, dynamic>{
      'Amount': amount,
      'Notes': notes,
      'Synced': 0,
    };

    if (lock != null) {
      updateData['Lock'] = lock;
    }

    await database.update(
      'ClientsPaying',
      updateData,
      where: 'Id = ?',
      whereArgs: [collectionId],
    );
  }

  // Add method to update collection lock status
  Future<void> updateCollectionLockStatus(
    int collectionId,
    String? lock,
  ) async {
    final database = await db;
    await database.update(
      'ClientsPaying',
      {'Lock': lock, 'Synced': 0},
      where: 'Id = ?',
      whereArgs: [collectionId],
    );
  }

  // Add method to update collection total and lock
  Future<void> updateCollectionAmountAndLock(
    int collectionId,
    double amount,
    String? lock,
  ) async {
    final database = await db;
    await database.update(
      'ClientsPaying',
      {'Amount': amount, 'Lock': lock, 'Synced': 0},
      where: 'Id = ?',
      whereArgs: [collectionId],
    );
  }

  // NEW: Method to get pending updated collections (similar to bills)
  Future<List<Map<String, dynamic>>> getPendingUpdatedCollections() async {
    final database = await db;

    // Get the current user ID from shared preferences
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) return [];

    return database.query(
      'ClientsPaying',
      where: 'Synced = ? AND Bill IS NOT NULL AND UserId = ?',
      whereArgs: [0, userId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingCollections() async {
    final database = await db;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) return [];

    return database.query(
      'ClientsPaying',
      where: 'Synced = ? AND UserId = ?',
      whereArgs: [0, userId],
    );
  }

  Future<List<Map<String, dynamic>>> getUserCollections(int userId) async {
    final database = await db;
    return database.query(
      'ClientsPaying',
      where: 'UserId = ?',
      whereArgs: [userId],
      orderBy: 'TheDate DESC',
    );
  }

  Future<Map<String, dynamic>?> getCollectionById(int collectionId) async {
    final database = await db;
    final result = await database.query(
      'ClientsPaying',
      where: 'Id = ?',
      whereArgs: [collectionId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> markCollectionAsSynced(int collectionId) async {
    final database = await db;
    await database.update(
      'ClientsPaying',
      {'Synced': 1},
      where: 'Id = ?',
      whereArgs: [collectionId],
    );
  }

  Future<void> markCollectionAsPendingSync(int collectionId) async {
    final database = await db;
    await database.update(
      'ClientsPaying',
      {'Synced': 0},
      where: 'Id = ?',
      whereArgs: [collectionId],
    );
  }

  Future<void> updateCollectionIdAndNumberByLocalUuid(
    String localUuid,
    int newId,
    String newBill,
  ) async {
    final database = await db;
    // Update collection with server values
    await database.update(
      'ClientsPaying',
      {'Id': newId, 'Bill': newBill, 'Synced': 1},
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
    );
  }

  Future<void> storeCollections(List<Map<String, dynamic>> collections) async {
    final database = await db;
    final batch = database.batch();

    for (final collection in collections) {
      batch.insert('ClientsPaying', {
        ...collection,
        'Synced': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ==============================
  //! Exchange / ExchangeBills Methods
  // ==============================

  /// Store exchange bills from server (marked as synced)
  Future<void> storeExchangeBills(List<Map<String, dynamic>> bills) async {
    final database = await db;
    final batch = database.batch();
    for (final bill in bills) {
      batch.insert('ExchangeBills', {
        ...bill,
        'Synced': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Store exchange items from server (replaces existing items for those bills)
  Future<void> storeExchangeItems(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    final billIds = items.map((e) => e['BillId']).toSet();
    for (final billId in billIds) {
      if (billId != null) {
        batch.delete('Exchange', where: 'BillId = ?', whereArgs: [billId]);
      }
    }
    for (final item in items) {
      final exchangeData = {
        'BillId': item['BillId'],
        'Qty': item['Qty'],
        'QtyUnit': item['QtyUnit'],
        'Price': item['Price'],
        'Total': item['Total'],
        'ItemId': item['ItemId'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'],
        'BranchId': item['BranchId'],
        'DestBranchId': item['DestBranchId'],
        'Synced': 1,
      };
      batch.insert(
        'Exchange',
        exchangeData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get pending (unsynced) exchange bills for current user
  Future<List<Map<String, dynamic>>> getPendingExchangeBills() async {
    final database = await db;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) return [];
    return database.query(
      'ExchangeBills',
      where: 'Synced = ? AND UserId = ?',
      whereArgs: [0, userId],
    );
  }

  /// Get pending exchange items (unsynced)
  Future<List<Map<String, dynamic>>> getPendingExchangeItems() async {
    final database = await db;
    return database.query('Exchange', where: 'Synced = ?', whereArgs: [0]);
  }

  /// Retrieves exchange bills for a given user for the current day.
  Future<List<Map<String, dynamic>>> getUserExchangeBills(int userId) async {
    final database = await db;
    return database.query(
      'ExchangeBills',
      where: 'UserId = ?',
      whereArgs: [userId],
      orderBy: 'TheDate DESC',
    );
  }

  /// Get exchange items for a specific bill ID
  Future<List<Map<String, dynamic>>> getExchangeItemsByBillId(
    int billId,
  ) async {
    final database = await db;
    return database.query('Exchange', where: 'BillId = ?', whereArgs: [billId]);
  }

  /// Insert a single exchange bill (locally, unsynced)
  Future<void> insertExchangeBill(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
      'ExchangeBills',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert a single exchange item (locally, unsynced)
  Future<void> insertExchange(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
      'Exchange',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Batch insert exchange items for a bill
  Future<void> batchInsertExchange(
    List<Map<String, dynamic>> items,
    int billId, {
    String? localUuid,
  }) async {
    if (items.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final item in items) {
      final data = {
        'BillId': billId,
        'Qty': item['Qty'],
        'QtyUnit': item['QtyUnit'],
        'Price': item['Price'],
        'Total': item['Total'],
        'ItemId': item['ItemId'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'],
        'BranchId': item['BranchId'],
        'DestBranchId': item['DestBranchId'],
        'LocalUuid': localUuid,
        'Synced': 0,
      };
      batch.insert(
        'Exchange',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Replace all exchange items for a bill (used after server update)
  Future<void> replaceExchangeItems(
    int billId,
    List<Map<String, dynamic>> items,
  ) async {
    final database = await db;
    final batch = database.batch();
    batch.delete('Exchange', where: 'BillId = ?', whereArgs: [billId]);
    for (final item in items) {
      final data = {
        'BillId': billId,
        'Qty': item['Qty'],
        'QtyUnit': item['QtyUnit'],
        'Price': item['Price'],
        'Total': item['Total'],
        'ItemId': item['ItemId'],
        'UnitQty': item['UnitQty'],
        'TotalQty': item['TotalQty'],
        'BranchId': item['BranchId'],
        'DestBranchId': item['DestBranchId'],
        'Synced': 0,
      };
      batch.insert(
        'Exchange',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Mark an exchange bill as pending sync (set Synced = 0)
  Future<void> markExchangeBillAsPendingSync(int billId) async {
    final database = await db;
    await database.update(
      'ExchangeBills',
      {'Synced': 0},
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  /// Mark an exchange bill and its items as synced
  Future<void> markExchangeBillAsSynced(int billId) async {
    final database = await db;
    await database.update(
      'ExchangeBills',
      {'Synced': 1},
      where: 'Id = ?',
      whereArgs: [billId],
    );
    await database.update(
      'Exchange',
      {'Synced': 1},
      where: 'BillId = ?',
      whereArgs: [billId],
    );
  }

  Future<void> updateExchangeBillLockStatus(int billId, String? lock) async {
    final database = await db;
    await database.update(
      'ExchangeBills',
      {
        'Lock': lock,
        'Synced': 0, // Mark as not synced when lock changes
      },
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  /// Update exchange bill details (total)
  Future<void> updateExchangeBillDetails(int billId, double total) async {
    final database = await db;
    await database.update(
      'ExchangeBills',
      {'Total': total, 'Synced': 0},
      where: 'Id = ?',
      whereArgs: [billId],
    );
  }

  /// Get exchange bills that have been updated and need sync (Synced=0 and Bill exists)
  Future<List<Map<String, dynamic>>> getPendingUpdatedExchangeBills() async {
    final database = await db;
    return database.query(
      'ExchangeBills',
      where: 'Synced = ? AND Bill IS NOT NULL',
      whereArgs: [0],
    );
  }

  /// Create a new local exchange bill (unsynced)
  Future<Map<String, dynamic>> createLocalExchangeBill({
    required DateTime theDate,
    required int userId,
    required int branchId,
    required int destBranchId,
    double total = 0.0,
    String? lock,
    String? localUuid,
  }) async {
    final database = await db;
    final uuid = localUuid ?? DateTime.now().microsecondsSinceEpoch.toString();
    final formattedDate =
        '${theDate.year}-${theDate.month.toString().padLeft(2, '0')}-${theDate.day.toString().padLeft(2, '0')} ${theDate.hour.toString().padLeft(2, '0')}:${theDate.minute.toString().padLeft(2, '0')}:${theDate.second.toString().padLeft(2, '0')}';
    final data = {
      'Bill': null,
      'TheDate': formattedDate,
      'UserId': userId,
      'Total': total,
      'BranchId': branchId,
      'DestBranchId': destBranchId,
      'Lock': lock,
      'LocalUuid': uuid,
      'Synced': 0,
    };
    final id = await database.insert(
      'ExchangeBills',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return {'Id': id, 'LocalUuid': uuid};
  }

  /// After server sync, update local exchange bill with server ID and number
  Future<void> updateExchangeBillIdAndNumberByLocalUuid(
    String localUuid,
    int newId,
    String newBill,
  ) async {
    final database = await db;
    final rows = await database.query(
      'ExchangeBills',
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
      limit: 1,
    );
    int? oldId = rows.isNotEmpty ? rows.first['Id'] as int? : null;

    await database.update(
      'ExchangeBills',
      {'Id': newId, 'Bill': newBill, 'Synced': 1},
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
    );

    await database.update(
      'Exchange',
      {'BillId': newId},
      where: 'LocalUuid = ?',
      whereArgs: [localUuid],
    );

    if (oldId != null) {
      await database.update(
        'Exchange',
        {'BillId': newId},
        where: 'BillId = ?',
        whereArgs: [oldId],
      );
    }
  }

  /// Mark exchange bill as synced by its bill number (used when server returns success without ID)
  Future<void> markExchangeBillSynced(String bill) async {
    if (bill.isEmpty) return;
    final database = await db;
    await database.update(
      'ExchangeBills',
      {'Synced': 1},
      where: 'Bill = ?',
      whereArgs: [bill],
    );
  }

  /// Mark exchange items for a bill as synced
  Future<void> markExchangeItemsSynced(int billId) async {
    final database = await db;
    await database.update(
      'Exchange',
      {'Synced': 1},
      where: 'BillId = ?',
      whereArgs: [billId],
    );
  }
}
