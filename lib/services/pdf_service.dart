import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tatweer/services/local_db_service.dart';

class PdfService {
  // ============= SAFE STRING ============
  String? _getSafeString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.isNotEmpty ? value : null;
    return value.toString().isNotEmpty ? value.toString() : null;
  }

  // ============= SAFE DOUBLE ============
  double _getSafeDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  // ============= NUMBER FORMATTER ============
  String _formatNumber(double n) {
    if (n % 1 == 0) return n.toInt().toString();
    return n.toStringAsFixed(2).replaceAll(RegExp(r'\.0+$'), '');
  }

  // ============= FORMAT TIME AM/PM ============
  String _formatTime(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      int hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? "PM" : "AM";
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return "$hour:$minute $period";
    } catch (_) {
      return "";
    }
  }

  // ============= FETCH SETTINGS ============
  Future<Map<String, dynamic>> _getHeaderSettings() async {
    try {
      final rows = await LocalDbService.instance.getSettings();
      if (rows.isNotEmpty) {
        final row = rows.first;
        return {
          'Company': _getSafeString(row['Company']),
          'Address': _getSafeString(row['Address']),
          'Phones': _getSafeString(row['Phones']),
        };
      }
    } catch (_) {}
    return {'Company': null, 'Address': null, 'Phones': null};
  }

  // ================================================
  // GENERATE PDF - BILL
  // ================================================
  Future<Uint8List> generateBillPdf(
    Map<String, dynamic> billDetails,
    List<Map<String, dynamic>> billItems,
    String regionName,
    double totalAmount,
    double paiedAmount, {
    double discount = 0.0,
    double netTotal = 0.0,
    double pastAccount = 0.0,
    double billRest = 0.0,
    double totalRest = 0.0,
    bool hasInternet = false,
  }) async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/Amiri-Regular.ttf");
    final boldFont = pw.Font.ttf(fontData);
    final pdfTheme = pw.ThemeData.withFont(base: boldFont, bold: boldFont);

    final settings = await _getHeaderSettings();

    final billNumber = _getSafeString(billDetails['Bill']);
    final date = _getSafeString(billDetails['TheDate']);
    final dateOnly = date != null ? date.split(' ').first : null;
    final formattedTime = date != null ? _formatTime(date) : null;
    final clientName = _getSafeString(billDetails['ClientName']);

    final calculatedNetTotal = netTotal > 0
        ? netTotal
        : (totalAmount - discount);

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(25),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          // ================= HEADER (Company start, Address and Phones column end, no labels) =================
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (settings['Company'] != null)
                    pw.Text(
                      settings['Company']!,
                      textAlign: pw.TextAlign.left,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  if (settings['Address'] != null || settings['Phones'] != null)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (settings['Address'] != null)
                          pw.Text(
                            settings['Address']!,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (settings['Phones'] != null)
                          pw.Text(
                            settings['Phones']!,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(height: 1, thickness: 2),
              pw.SizedBox(height: 12),
            ],
          ),
          // ================= BILL INFO =================
          if (billNumber != null) _buildInfoRow('رقم الفاتورة:', billNumber),
          if (dateOnly != null)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  pw.Text(
                    'التاريخ:',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    dateOnly,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  if (formattedTime!.isNotEmpty)
                    pw.Text(
                      formattedTime,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          if (clientName != null) _buildInfoRow('العميل:', clientName),
          pw.SizedBox(height: 14),
          // ================= MULTI-PAGE TABLE =================
          _buildItemsTable(billItems),
          pw.SizedBox(height: 18),
          // ================= SUMMARY (2 items per row, small spaces, net last in box) =================
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12),
            child: pw.Column(
              children: _buildSummaryRows(
                totalAmount,
                discount,
                calculatedNetTotal,
                paiedAmount,
                billRest,
                totalRest,
                hasInternet,
              ),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ================================================
  // GENERATE PDF - COLLECTION BILL (UNCHANGED)
  // ================================================
  Future<Uint8List> generateCollectionPdf(
    Map<String, dynamic> collectionDetails,
    String regionName,
    double amount,
    String notes,
  ) async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/Amiri-Regular.ttf");
    final boldFont = pw.Font.ttf(fontData);
    final pdfTheme = pw.ThemeData.withFont(base: boldFont, bold: boldFont);

    final settings = await _getHeaderSettings();

    final billNumber = _getSafeString(collectionDetails['Bill']);
    final date = _getSafeString(collectionDetails['TheDate']);
    final dateOnly = date != null ? date.split(' ').first : null;
    final formattedTime = date != null ? _formatTime(date) : null;
    final clientName = _getSafeString(collectionDetails['ClientName']);

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(25),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          // ================= HEADER =================
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (settings['Company'] != null)
                    pw.Text(
                      settings['Company']!,
                      textAlign: pw.TextAlign.left,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  if (settings['Address'] != null || settings['Phones'] != null)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (settings['Address'] != null)
                          pw.Text(
                            settings['Address']!,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (settings['Phones'] != null)
                          pw.Text(
                            settings['Phones']!,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(height: 1, thickness: 2),
              pw.SizedBox(height: 12),
            ],
          ),

          // ================= TITLE =================
          pw.Center(
            child: pw.Text(
              'فاتورة تحصيل',
              style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 20),

          // ================= COLLECTION INFO =================
          if (billNumber != null) _buildInfoRow('رقم الفاتورة:', billNumber),
          if (dateOnly != null)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  pw.Text(
                    'التاريخ:',
                    style: pw.TextStyle(
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    dateOnly,
                    style: pw.TextStyle(
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  if (formattedTime!.isNotEmpty)
                    pw.Text(
                      formattedTime,
                      style: pw.TextStyle(
                        fontSize: 26,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          if (clientName != null) _buildInfoRow('العميل:', clientName),
          if (regionName != 'غير معروف') _buildInfoRow('المنطقة:', regionName),
          pw.SizedBox(height: 20),

          // ================= AMOUNT SECTION =================
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 2),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [
                pw.Text(
                  'المبلغ: ',
                  style: pw.TextStyle(
                    fontSize: 27,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  '${_formatNumber(amount)} ج.م',
                  style: pw.TextStyle(
                    fontSize: 27,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // ================= NOTES SECTION =================
          if (notes.isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ملاحظات:',
                  style: pw.TextStyle(
                    fontSize: 25,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 1),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    notes,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  // ================================================
  // GENERATE PDF - BUYS BILL
  // ================================================
  Future<Uint8List> generateBuysBillPdf(
    Map<String, dynamic> billDetails,
    List<Map<String, dynamic>> billItems,
    String sellerName,
    double totalAmount,
    double paiedAmount, {
    double discount = 0.0,
    double netTotal = 0.0,
    double pastAccount = 0.0,
    double billRest = 0.0,
    double totalRest = 0.0,
    bool hasInternet = false,
  }) async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/Amiri-Regular.ttf");
    final boldFont = pw.Font.ttf(fontData);
    final pdfTheme = pw.ThemeData.withFont(base: boldFont, bold: boldFont);

    final settings = await _getHeaderSettings();

    final billNumber = _getSafeString(billDetails['Bill']);
    final date = _getSafeString(billDetails['TheDate']);
    final dateOnly = date != null ? date.split(' ').first : null;
    final formattedTime = date != null ? _formatTime(date) : null;

    final calculatedNetTotal = netTotal > 0
        ? netTotal
        : (totalAmount - discount);

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(25),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          // ================= HEADER (Company start, Address and Phones column end, no labels) =================
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (settings['Company'] != null)
                    pw.Text(
                      settings['Company']!,
                      textAlign: pw.TextAlign.left,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  if (settings['Address'] != null || settings['Phones'] != null)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (settings['Address'] != null)
                          pw.Text(
                            settings['Address']!,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (settings['Phones'] != null)
                          pw.Text(
                            settings['Phones']!,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(height: 1, thickness: 2),
              pw.SizedBox(height: 12),
            ],
          ),
          // ================= BILL INFO =================
          if (billNumber != null) _buildInfoRow('رقم الفاتورة:', billNumber),
          if (dateOnly != null)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  pw.Text(
                    'التاريخ:',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    dateOnly,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  if (formattedTime!.isNotEmpty)
                    pw.Text(
                      formattedTime,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          _buildInfoRow('المورد:', sellerName),
          pw.SizedBox(height: 14),
          // ================= MULTI-PAGE TABLE =================
          _buildItemsTable(billItems),
          pw.SizedBox(height: 18),
          // ================= SUMMARY (2 items per row, small spaces, net last in box) =================
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12),
            child: pw.Column(
              children: _buildSummaryRows(
                totalAmount,
                discount,
                calculatedNetTotal,
                paiedAmount,
                billRest,
                totalRest,
                hasInternet,
              ),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ================================================
  // INFO ROW (label + value)
  // ================================================
  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================
  // MULTI-PAGE TABLE (centered cells)
  // ================================================
  pw.Widget _buildItemsTable(List<Map<String, dynamic>> items) {
    final headers = ['الإجمالي', 'النوع', 'السعر', 'الكمية', 'الوحدة', 'الصنف'];
    final data = items.map((item) {
      return [
        _formatNumber(_getSafeDouble(item['Total'])),
        _getSafeString(item['Type']) ?? '',
        _formatNumber(_getSafeDouble(item['Price'])),
        _formatNumber(_getSafeDouble(item['Qty'])),
        _getSafeString(item['QtyUnit']) ?? '',
        _getSafeString(item['ItemName']) ?? '',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(width: 1.0),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22),
      cellStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      cellHeight: 30,
    );
  }

  // ================================================
  // BUILD SUMMARY ROWS (pairs, small spacing, net in box at end)
  // ================================================
  List<pw.Widget> _buildSummaryRows(
    double totalAmount,
    double discount,
    double calculatedNetTotal,
    double paiedAmount,
    double billRest,
    double totalRest,
    bool hasInternet,
  ) {
    final pairs = <Map<String, String>>[
      {'label': 'إجمالي الفاتورة: ', 'value': _formatNumber(totalAmount)},
      {'label': 'الخصم: ', 'value': _formatNumber(discount)},
      {'label': 'المدفوع: ', 'value': _formatNumber(paiedAmount)},
      {'label': 'باقي الفاتورة: ', 'value': _formatNumber(billRest)},
    ];

    // 💡 NEW: Only add total rest if there is internet and it's calculated
    if (hasInternet) {
      pairs.add({'label': 'الباقي الكلي: ', 'value': _formatNumber(totalRest)});
    }

    final rows = <pw.Widget>[];
    for (var i = 0; i < pairs.length; i += 2) {
      final left = pairs[i];
      final right = (i + 1 < pairs.length) ? pairs[i + 1] : null;
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.Text(
                      left['label']!,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 2),
                    pw.Text(
                      left['value']!,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              if (right != null)
                pw.Expanded(
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    children: [
                      pw.Text(
                        right['label']!,
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 2),
                      pw.Text(
                        right['value']!,
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                pw.Expanded(child: pw.Container()),
            ],
          ),
        ),
      );
    }

    // Add net total last, in a box
    rows.add(pw.SizedBox(height: 12));
    rows.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 2),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            pw.Text(
              'صافي الفاتورة: ',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(width: 2),
            pw.Text(
              _formatNumber(calculatedNetTotal),
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    return rows;
  }

  // ================================================
  // GENERATE PDF - EXCHANGE BILL (SIMPLIFIED)
  // ================================================
  Future<Uint8List> generateExchangeBillPdf(
    Map<String, dynamic> billDetails,
    List<Map<String, dynamic>> billItems,
    String fromBranchName,
    String toBranchName,
    double totalAmount,
  ) async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/Amiri-Regular.ttf");
    final boldFont = pw.Font.ttf(fontData);
    final pdfTheme = pw.ThemeData.withFont(base: boldFont, bold: boldFont);

    final settings = await _getHeaderSettings();

    final billNumber = _getSafeString(billDetails['Bill']);
    final date = _getSafeString(billDetails['TheDate']);
    final dateOnly = date != null ? date.split(' ').first : null;
    final formattedTime = date != null ? _formatTime(date) : null;

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(25),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          // Header
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (settings['Company'] != null)
                    pw.Text(
                      settings['Company']!,
                      textAlign: pw.TextAlign.left,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  if (settings['Address'] != null || settings['Phones'] != null)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (settings['Address'] != null)
                          pw.Text(
                            settings['Address']!,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (settings['Phones'] != null)
                          pw.Text(
                            settings['Phones']!,
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(height: 1, thickness: 2),
              pw.SizedBox(height: 12),
            ],
          ),
          // Bill info
          if (billNumber != null) _buildInfoRow('رقم الفاتورة:', billNumber),
          if (dateOnly != null)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  pw.Text(
                    'التاريخ:',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    dateOnly,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  if (formattedTime!.isNotEmpty)
                    pw.Text(
                      formattedTime,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          _buildInfoRow('من فرع:', fromBranchName),
          _buildInfoRow('إلى فرع:', toBranchName),
          pw.SizedBox(height: 14),
          // Items table (same as sells but without pricing/type)
          _buildExchangeItemsTable(billItems),
          pw.SizedBox(height: 18),
          // Total only
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 2),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [
                pw.Text(
                  'إجمالي الفاتورة: ',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(width: 2),
                pw.Text(
                  '${_formatNumber(totalAmount)} ج.م',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildExchangeItemsTable(List<Map<String, dynamic>> items) {
    final headers = ['الإجمالي', 'السعر', 'الكمية', 'الوحدة', 'الصنف'];
    final data = items.map((item) {
      return [
        _formatNumber(_getSafeDouble(item['Total'])),
        _formatNumber(_getSafeDouble(item['Price'])),
        _formatNumber(_getSafeDouble(item['Qty'])),
        _getSafeString(item['QtyUnit']) ?? '',
        _getSafeString(item['ItemName']) ?? '',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(width: 1.0),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22),
      cellStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      cellHeight: 30,
    );
  }
}
