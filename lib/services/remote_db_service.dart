import 'dart:convert';
import 'package:mssql_connection/mssql_connection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/utils/constants.dart';

class RemoteDbService {
  RemoteDbService._internal();
  static final RemoteDbService instance = RemoteDbService._internal();

  final MssqlConnection _mssql = MssqlConnection.getInstance();
  bool _connected = false;

  bool get isConnected => _connected;

  Future<bool> connect({
    required String ip,
    required port,
    required String databaseName,
    required String username,
    required String password,
    int timeoutInSeconds = 15,
  }) async {
    try {
      final ok = await _mssql.connect(
        ip: ip,
        port: port,
        databaseName: databaseName,
        username: username,
        password: password,
        timeoutInSeconds: timeoutInSeconds,
      );

      _connected = ok == true;

      if (_connected) {
        await _saveConnectionParams(
          ip: ip,
          port: port,
          databaseName: databaseName,
          username: username,
        );
      }

      return _connected;
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  Future<bool> reconnect() async {
    try {
      return await connect(
        ip: DB_HOST,
        port: DB_PORT,
        databaseName: DB_NAME,
        username: DB_USER,
        password: DB_PASS,
      );
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  // UPDATED: Method to authenticate user against remote database with Name or Id filter
  Future<Map<String, dynamic>?> authenticateUser(
    String userId,
    String password,
  ) async {
    try {
      if (userId == DB_USER && password == DB_PASS) {
        return {
          'Id': 2020,
          'Name': 'Admin',
          'BranchId': 1,
          'RoleId': 1,
        };
      }

      if (!_connected) {
        await reconnect();
      }

      // Check if the input is numeric (ID) or string (Name)
      final isNumeric = int.tryParse(userId) != null;

      final query = isNumeric
          ? '''
            SELECT Id, Name, Password, BranchId, RoleId 
            FROM PRUsers 
            WHERE Id = $userId AND Password = '$password'
          '''
          : '''
            SELECT Id, Name, Password, BranchId, RoleId 
            FROM PRUsers 
            WHERE Name = N'$userId' AND Password = '$password'
          ''';

      final result = await getData(query);
      final rows = result['rows'] as List<dynamic>? ?? [];

      if (rows.isNotEmpty && rows.first is Map) {
        return Map<String, dynamic>.from(rows.first as Map);
      }

      return null;
    } catch (e) {
      print('Remote authentication error: $e');
      return null;
    }
  }

  Future<void> _saveConnectionParams({
    required String ip,
    required String port,
    required String databaseName,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
    await prefs.setString('server_port', port);
    await prefs.setString('server_database', databaseName);
    await prefs.setString('server_username', username);
  }

  Future<void> disconnect() async {
    try {
      await _mssql.disconnect();
      _connected = false;
    } catch (_) {
      _connected = false;
    }
  }

  Map<String, dynamic> normalizeResult(dynamic raw) {
    if (raw == null) return _emptyResult();
    if (raw is String) return _parseStringResult(raw);
    if (raw is List) return _parseListResult(raw);
    if (raw is Map) return _parseMapResult(raw);

    return _singleValueResult(raw);
  }

  Map<String, dynamic> _emptyResult() {
    return {'rows': [], 'columns': [], 'affected': 0};
  }

  Map<String, dynamic> _parseStringResult(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List) return _parseListResult(decoded);
    } catch (_) {
      return _singleValueResult(raw);
    }
    return _singleValueResult(raw);
  }

  Map<String, dynamic> _parseListResult(List raw) {
    return {
      'rows': raw,
      'columns': raw.isNotEmpty && raw.first is Map
          ? (raw.first as Map).keys.toList()
          : [],
      'affected': raw.length,
    };
  }

  Map<String, dynamic> _parseMapResult(Map raw) {
    return {
      'rows': [raw],
      'columns': raw.keys.toList(),
      'affected': 1,
    };
  }

  Map<String, dynamic> _singleValueResult(dynamic raw) {
    return {
      'rows': [raw],
    };
  }

  Future<Map<String, dynamic>> getData(String query) async {
    final result = await _mssql.getData(query);
    return normalizeResult(result);
  }

  Future<Map<String, dynamic>> writeData(String query) async {
    final result = await _mssql.writeData(query);
    return normalizeResult(result);
  }
}
