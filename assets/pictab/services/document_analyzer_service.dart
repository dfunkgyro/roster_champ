import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/document_type.dart' as doc;
import '../models/roster.dart';
import '../models/data_table.dart';

/// Service for analyzing images and extracting structured data
class DocumentAnalyzerService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  /// Analyze an image file and return the analysis result
  Future<doc.DocumentAnalysisResult> analyzeImage(File imageFile) async {
    try {
      // Perform OCR
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      // Convert ML Kit results to our model
      final textBlocks = _convertTextBlocks(recognizedText);
      final rawLines = _extractRawLines(recognizedText);

      // Determine document type
      final documentType = _detectDocumentType(rawLines, textBlocks);

      // Extract data based on document type
      final extractedData = await _extractData(documentType, rawLines, textBlocks);

      return doc.DocumentAnalysisResult(
        type: documentType.type,
        confidence: documentType.confidence,
        extractedData: extractedData,
        rawTextLines: rawLines,
        textBlocks: textBlocks,
      );
    } catch (e) {
      return doc.DocumentAnalysisResult.error('Failed to analyze image: $e');
    }
  }

  /// Convert ML Kit text blocks to our model
  List<doc.TextBlock> _convertTextBlocks(RecognizedText recognizedText) {
    return recognizedText.blocks.map((block) {
      return doc.TextBlock(
        text: block.text,
        boundingBox: doc.Rect(
          left: block.boundingBox.left,
          top: block.boundingBox.top,
          right: block.boundingBox.right,
          bottom: block.boundingBox.bottom,
        ),
        lines: block.lines.map((line) {
          return doc.TextLine(
            text: line.text,
            boundingBox: doc.Rect(
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
            ),
          );
        }).toList(),
      );
    }).toList();
  }

  /// Extract raw text lines from recognized text
  List<String> _extractRawLines(RecognizedText recognizedText) {
    final lines = <String>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        lines.add(line.text);
      }
    }
    return lines;
  }

  /// Detect the type of document based on content analysis
  _DocumentTypeResult _detectDocumentType(
    List<String> lines,
    List<doc.TextBlock> blocks,
  ) {
    final allText = lines.join(' ').toLowerCase();

    // Check for roster indicators
    final rosterScore = _calculateRosterScore(lines, allText);
    if (rosterScore >= 0.6) {
      return _DocumentTypeResult(doc.DocumentType.roster, rosterScore);
    }

    // Check for invoice indicators
    final invoiceScore = _calculateInvoiceScore(allText);
    if (invoiceScore >= 0.6) {
      return _DocumentTypeResult(doc.DocumentType.invoice, invoiceScore);
    }

    // Check for receipt indicators
    final receiptScore = _calculateReceiptScore(allText);
    if (receiptScore >= 0.6) {
      return _DocumentTypeResult(doc.DocumentType.receipt, receiptScore);
    }

    // Check for table structure
    final tableScore = _calculateTableScore(lines, blocks);
    if (tableScore >= 0.4) {
      return _DocumentTypeResult(doc.DocumentType.table, tableScore);
    }

    // Check for form indicators
    final formScore = _calculateFormScore(allText);
    if (formScore >= 0.5) {
      return _DocumentTypeResult(doc.DocumentType.form, formScore);
    }

    return _DocumentTypeResult(doc.DocumentType.unknown, 0.0);
  }

  /// Calculate roster detection score
  double _calculateRosterScore(List<String> lines, String allText) {
    double score = 0.0;

    // Check for day names
    final dayPatterns = [
      'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun',
      'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
    ];
    for (final day in dayPatterns) {
      if (allText.contains(day)) {
        score += 0.1;
      }
    }

    // Check for month names
    final monthPatterns = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
      'january', 'february', 'march', 'april', 'june',
      'july', 'august', 'september', 'october', 'november', 'december',
    ];
    for (final month in monthPatterns) {
      if (allText.contains(month)) {
        score += 0.15;
      }
    }

    // Check for shift codes
    final shiftPatterns = [
      RegExp(r'\bN12\b', caseSensitive: false),
      RegExp(r'\bA/L\b', caseSensitive: false),
      RegExp(r'\bAD\b'),
      RegExp(r'\bTr\b'),
      RegExp(r'\bSick\b', caseSensitive: false),
    ];
    for (final pattern in shiftPatterns) {
      if (pattern.hasMatch(allText)) {
        score += 0.15;
      }
    }

    // Check for repeating single letters (common in rosters)
    final singleLetterCount = RegExp(r'\b[RDECLNS]\b').allMatches(allText.toUpperCase()).length;
    if (singleLetterCount > 10) {
      score += 0.2;
    }

    // Check for numeric date patterns
    final datePattern = RegExp(r'\b\d{1,2}\b');
    final dateMatches = datePattern.allMatches(allText).length;
    if (dateMatches > 10) {
      score += 0.15;
    }

    // Check for keywords
    final keywords = ['roster', 'schedule', 'shift', 'rota', 'staff', 'employee'];
    for (final keyword in keywords) {
      if (allText.contains(keyword)) {
        score += 0.2;
      }
    }

    return min(score, 1.0);
  }

  /// Calculate invoice detection score
  double _calculateInvoiceScore(String allText) {
    double score = 0.0;
    final keywords = [
      'invoice', 'bill to', 'ship to', 'subtotal', 'total', 'tax',
      'payment', 'due date', 'invoice number', 'po number',
    ];
    for (final keyword in keywords) {
      if (allText.contains(keyword)) {
        score += 0.15;
      }
    }
    return min(score, 1.0);
  }

  /// Calculate receipt detection score
  double _calculateReceiptScore(String allText) {
    double score = 0.0;
    final keywords = [
      'receipt', 'thank you', 'change', 'cash', 'card',
      'subtotal', 'total', 'tax', 'qty', 'item',
    ];
    for (final keyword in keywords) {
      if (allText.contains(keyword)) {
        score += 0.15;
      }
    }
    return min(score, 1.0);
  }

  /// Calculate table detection score
  double _calculateTableScore(List<String> lines, List<doc.TextBlock> blocks) {
    double score = 0.0;

    // Check for consistent column structure
    if (blocks.length > 3) {
      score += 0.3;
    }

    // Check for aligned text blocks (indicating table structure)
    final leftPositions = blocks.map((b) => b.boundingBox.left).toList();
    final uniqueLeftPositions = leftPositions.toSet();
    if (uniqueLeftPositions.length >= 2 && uniqueLeftPositions.length <= 10) {
      score += 0.3;
    }

    // Check for multiple rows with similar structure
    if (lines.length > 5) {
      score += 0.2;
    }

    return min(score, 1.0);
  }

  /// Calculate form detection score
  double _calculateFormScore(String allText) {
    double score = 0.0;
    final keywords = [
      'name:', 'date:', 'address:', 'phone:', 'email:',
      'signature', 'please fill', 'required', 'form',
    ];
    for (final keyword in keywords) {
      if (allText.contains(keyword)) {
        score += 0.15;
      }
    }
    return min(score, 1.0);
  }

  /// Extract data based on document type
  Future<Map<String, dynamic>> _extractData(
    _DocumentTypeResult typeResult,
    List<String> lines,
    List<doc.TextBlock> blocks,
  ) async {
    switch (typeResult.type) {
      case doc.DocumentType.roster:
        return _extractRosterData(lines, blocks);
      case doc.DocumentType.table:
        return _extractTableData(lines, blocks);
      case doc.DocumentType.invoice:
      case doc.DocumentType.receipt:
      case doc.DocumentType.form:
        return _extractGenericData(lines, blocks);
      case doc.DocumentType.unknown:
        return {'rawText': lines.join('\n')};
    }
  }

  /// Extract roster data from text
  Map<String, dynamic> _extractRosterData(
    List<String> lines,
    List<doc.TextBlock> blocks,
  ) {
    // Sort blocks by vertical position to get rows
    final sortedBlocks = List<doc.TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // Group blocks by row (similar vertical position)
    final rows = _groupBlocksByRow(sortedBlocks);

    // Identify header rows (dates, days)
    final dates = _extractDates(rows);
    final employees = _extractEmployees(rows, dates);

    // Detect date range
    DateTime? startDate;
    DateTime? endDate;
    if (dates.isNotEmpty) {
      startDate = dates.first;
      endDate = dates.last;
    } else {
      // Default to current month if no dates detected
      final now = DateTime.now();
      startDate = DateTime(now.year, now.month, 1);
      endDate = DateTime(now.year, now.month + 1, 0);
    }

    return {
      'type': 'roster',
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'dates': dates.map((d) => d.toIso8601String()).toList(),
      'employees': employees,
      'rowCount': rows.length,
    };
  }

  /// Group text blocks by row based on vertical position
  List<List<doc.TextBlock>> _groupBlocksByRow(List<doc.TextBlock> blocks) {
    if (blocks.isEmpty) return [];

    final rows = <List<doc.TextBlock>>[];
    var currentRow = <doc.TextBlock>[blocks.first];
    var currentTop = blocks.first.boundingBox.top;
    const tolerance = 20.0; // Pixels tolerance for same row

    for (var i = 1; i < blocks.length; i++) {
      final block = blocks[i];
      if ((block.boundingBox.top - currentTop).abs() <= tolerance) {
        currentRow.add(block);
      } else {
        // Sort current row by horizontal position
        currentRow.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
        rows.add(currentRow);
        currentRow = [block];
        currentTop = block.boundingBox.top;
      }
    }

    // Add last row
    if (currentRow.isNotEmpty) {
      currentRow.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      rows.add(currentRow);
    }

    return rows;
  }

  /// Extract dates from header rows
  List<DateTime> _extractDates(List<List<doc.TextBlock>> rows) {
    final dates = <DateTime>[];
    final now = DateTime.now();
    var currentMonth = now.month;
    var currentYear = now.year;

    // Look for month names to determine the month
    for (final row in rows.take(3)) {
      for (final block in row) {
        final text = block.text.toLowerCase();
        final monthIndex = _getMonthIndex(text);
        if (monthIndex != null) {
          currentMonth = monthIndex;
          break;
        }
      }
    }

    // Look for date numbers
    for (final row in rows.take(5)) {
      for (final block in row) {
        final text = block.text.trim();
        final num = int.tryParse(text);
        if (num != null && num >= 1 && num <= 31) {
          try {
            final date = DateTime(currentYear, currentMonth, num);
            if (!dates.contains(date)) {
              dates.add(date);
            }
          } catch (_) {}
        }
      }
    }

    dates.sort();
    return dates;
  }

  /// Get month index from text
  int? _getMonthIndex(String text) {
    final months = {
      'january': 1, 'jan': 1,
      'february': 2, 'feb': 2,
      'march': 3, 'mar': 3,
      'april': 4, 'apr': 4,
      'may': 5,
      'june': 6, 'jun': 6,
      'july': 7, 'jul': 7,
      'august': 8, 'aug': 8,
      'september': 9, 'sep': 9,
      'october': 10, 'oct': 10,
      'november': 11, 'nov': 11,
      'december': 12, 'dec': 12,
    };
    return months[text.toLowerCase()];
  }

  /// Extract employee data from rows
  List<Map<String, dynamic>> _extractEmployees(
    List<List<doc.TextBlock>> rows,
    List<DateTime> dates,
  ) {
    final employees = <Map<String, dynamic>>[];
    final shiftPattern = RegExp(r'^[RNDECLSW]$|^N12$|^A/L$|^AD$|^Tr$|^Sick$', caseSensitive: false);

    // Skip header rows (usually first 3-4 rows)
    for (var i = 3; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      // First cell is usually the employee name
      final nameBlock = row.first;
      final name = nameBlock.text.trim();

      // Skip if name looks like a header or date
      if (name.isEmpty ||
          _getMonthIndex(name) != null ||
          int.tryParse(name) != null ||
          name.length < 2) {
        continue;
      }

      // Extract shifts from remaining cells
      final shifts = <String, String>{};
      var dateIndex = 0;

      for (var j = 1; j < row.length && dateIndex < dates.length; j++) {
        final cellText = row[j].text.trim().toUpperCase();

        // Check if it looks like a shift code
        if (shiftPattern.hasMatch(cellText) || cellText.length <= 4) {
          final dateKey = _dateToKey(dates[dateIndex]);
          shifts[dateKey] = cellText.isEmpty ? 'R' : cellText;
          dateIndex++;
        }
      }

      if (name.isNotEmpty) {
        employees.add({
          'name': name,
          'shifts': shifts,
        });
      }
    }

    return employees;
  }

  /// Extract generic table data
  Map<String, dynamic> _extractTableData(
    List<String> lines,
    List<doc.TextBlock> blocks,
  ) {
    final sortedBlocks = List<doc.TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final rows = _groupBlocksByRow(sortedBlocks);

    // Convert to 2D list
    final tableData = rows.map((row) {
      return row.map((block) => block.text.trim()).toList();
    }).toList();

    // Determine headers (first row)
    final headers = tableData.isNotEmpty ? tableData.first : <String>[];
    final dataRows = tableData.length > 1 ? tableData.skip(1).toList() : <List<String>>[];

    return {
      'type': 'table',
      'headers': headers,
      'rows': dataRows,
      'rowCount': dataRows.length,
      'columnCount': headers.length,
    };
  }

  /// Extract generic data for invoices, receipts, forms
  Map<String, dynamic> _extractGenericData(
    List<String> lines,
    List<doc.TextBlock> blocks,
  ) {
    final data = <String, dynamic>{
      'rawLines': lines,
      'fields': <String, String>{},
    };

    // Try to extract key-value pairs
    for (final line in lines) {
      if (line.contains(':')) {
        final parts = line.split(':');
        if (parts.length == 2) {
          final key = parts[0].trim();
          final value = parts[1].trim();
          if (key.isNotEmpty && value.isNotEmpty) {
            data['fields'][key] = value;
          }
        }
      }
    }

    return data;
  }

  String _dateToKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Create a Roster object from extracted data
  Roster? createRosterFromData(Map<String, dynamic> extractedData) {
    if (extractedData['type'] != 'roster') return null;

    try {
      final startDate = DateTime.parse(extractedData['startDate'] as String);
      final endDate = DateTime.parse(extractedData['endDate'] as String);
      final employeesData = extractedData['employees'] as List<dynamic>? ?? [];

      final employees = employeesData.map((e) {
        final data = e as Map<String, dynamic>;
        return Employee(
          name: data['name'] as String,
          shifts: (data['shifts'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as String),
              ) ??
              {},
        );
      }).toList();

      return Roster(
        startDate: startDate,
        endDate: endDate,
        employees: employees,
      );
    } catch (e) {
      return null;
    }
  }

  /// Create a DataTable from extracted data
  ExtractedDataTable? createTableFromData(Map<String, dynamic> extractedData) {
    if (extractedData['type'] != 'table') return null;

    try {
      final headers = (extractedData['headers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];
      final rows = (extractedData['rows'] as List<dynamic>?)
              ?.map((row) =>
                  (row as List<dynamic>).map((cell) => cell as String).toList())
              .toList() ??
          [];

      return ExtractedDataTable.fromList(
        [headers, ...rows],
        firstRowIsHeader: true,
      );
    } catch (e) {
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    _textRecognizer.close();
  }
}

class _DocumentTypeResult {
  final doc.DocumentType type;
  final double confidence;

  _DocumentTypeResult(this.type, this.confidence);
}
