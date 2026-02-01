import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import '../models/document_type.dart' as doc;
import '../models/roster.dart';
import '../models/data_table.dart';
import 'document_analyzer_service.dart';

/// Supported file types for processing
enum FileType {
  image, // JPG, PNG, etc.
  pdf,
  csv,
  unknown,
}

/// Result of file processing
class FileProcessingResult {
  final FileType fileType;
  final doc.DocumentAnalysisResult? analysisResult;
  final Roster? roster;
  final ExtractedDataTable? dataTable;
  final String? errorMessage;
  final File? processedImageFile; // For preview purposes

  FileProcessingResult({
    required this.fileType,
    this.analysisResult,
    this.roster,
    this.dataTable,
    this.errorMessage,
    this.processedImageFile,
  });

  bool get isSuccessful => errorMessage == null;

  factory FileProcessingResult.error(String message, FileType type) {
    return FileProcessingResult(
      fileType: type,
      errorMessage: message,
    );
  }
}

/// Service for processing different file types
class FileProcessorService {
  final DocumentAnalyzerService _analyzerService;

  FileProcessorService(this._analyzerService);

  /// Determine file type from extension
  FileType getFileType(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;

    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return FileType.image;
      case 'pdf':
        return FileType.pdf;
      case 'csv':
        return FileType.csv;
      default:
        return FileType.unknown;
    }
  }

  /// Process any supported file type
  Future<FileProcessingResult> processFile(File file) async {
    final fileType = getFileType(file.path);

    switch (fileType) {
      case FileType.image:
        return _processImage(file);
      case FileType.pdf:
        return _processPdf(file);
      case FileType.csv:
        return _processCsv(file);
      case FileType.unknown:
        return FileProcessingResult.error(
          'Unsupported file type. Please use JPG, PNG, PDF, or CSV files.',
          fileType,
        );
    }
  }

  /// Process image files (JPG, PNG)
  Future<FileProcessingResult> _processImage(File file) async {
    try {
      final analysisResult = await _analyzerService.analyzeImage(file);

      return FileProcessingResult(
        fileType: FileType.image,
        analysisResult: analysisResult,
        processedImageFile: file,
      );
    } catch (e) {
      return FileProcessingResult.error(
        'Failed to process image: $e',
        FileType.image,
      );
    }
  }

  /// Process PDF files - converts pages to images then runs OCR
  Future<FileProcessingResult> _processPdf(File file) async {
    try {
      // Open PDF document
      final document = await PdfDocument.openFile(file.path);
      final pageCount = document.pagesCount;

      if (pageCount == 0) {
        await document.close();
        return FileProcessingResult.error(
          'PDF has no pages',
          FileType.pdf,
        );
      }

      // For roster detection, we typically only need the first page
      // but we'll process all pages and combine results
      final allTextLines = <String>[];
      final allTextBlocks = <doc.TextBlock>[];
      File? firstPageImage;

      for (int i = 1; i <= pageCount; i++) {
        final page = await document.getPage(i);

        // Render page to image
        final pageImage = await page.render(
          width: page.width * 2, // 2x scale for better OCR
          height: page.height * 2,
          format: PdfPageImageFormat.png,
        );

        await page.close();

        if (pageImage == null) continue;

        // Save image temporarily
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/pdf_page_$i.png');
        await tempFile.writeAsBytes(pageImage.bytes);

        // Keep first page for preview
        if (i == 1) {
          firstPageImage = tempFile;
        }

        // Run OCR on the page image
        final pageResult = await _analyzerService.analyzeImage(tempFile);
        allTextLines.addAll(pageResult.rawTextLines);
        allTextBlocks.addAll(pageResult.textBlocks);

        // Clean up temp files (except first page)
        if (i > 1) {
          await tempFile.delete();
        }
      }

      await document.close();

      // Combine results and re-analyze for document type
      final combinedResult = doc.DocumentAnalysisResult(
        type: _detectTypeFromText(allTextLines),
        confidence: 0.7, // PDF extraction is generally reliable
        extractedData: _extractDataFromText(allTextLines, allTextBlocks),
        rawTextLines: allTextLines,
        textBlocks: allTextBlocks,
      );

      return FileProcessingResult(
        fileType: FileType.pdf,
        analysisResult: combinedResult,
        processedImageFile: firstPageImage,
      );
    } catch (e) {
      return FileProcessingResult.error(
        'Failed to process PDF: $e',
        FileType.pdf,
      );
    }
  }

  /// Process CSV files - direct parsing, no OCR needed
  Future<FileProcessingResult> _processCsv(File file) async {
    try {
      final contents = await file.readAsString();
      final rows = const CsvToListConverter().convert(contents);

      if (rows.isEmpty) {
        return FileProcessingResult.error(
          'CSV file is empty',
          FileType.csv,
        );
      }

      // Convert to string lists
      final stringRows = rows.map((row) {
        return row.map((cell) => cell.toString()).toList();
      }).toList();

      // Check if this looks like a roster
      final isRoster = _csvLooksLikeRoster(stringRows);

      if (isRoster) {
        // Parse as roster
        final roster = _parseRosterFromCsv(stringRows);
        if (roster != null) {
          return FileProcessingResult(
            fileType: FileType.csv,
            roster: roster,
            analysisResult: doc.DocumentAnalysisResult(
              type: doc.DocumentType.roster,
              confidence: 0.9,
              extractedData: {'source': 'csv', 'rows': rows.length},
              rawTextLines: stringRows.map((r) => r.join(',')).toList(),
            ),
          );
        }
      }

      // Parse as generic table
      final table = ExtractedDataTable.fromList(
        stringRows,
        firstRowIsHeader: true,
      );
      table.title = file.path.split('/').last.replaceAll('.csv', '');

      return FileProcessingResult(
        fileType: FileType.csv,
        dataTable: table,
        analysisResult: doc.DocumentAnalysisResult(
          type: doc.DocumentType.table,
          confidence: 0.95,
          extractedData: {
            'source': 'csv',
            'rows': table.rowCount,
            'columns': table.columnCount,
          },
          rawTextLines: stringRows.map((r) => r.join(',')).toList(),
        ),
      );
    } catch (e) {
      return FileProcessingResult.error(
        'Failed to process CSV: $e',
        FileType.csv,
      );
    }
  }

  /// Check if CSV looks like a roster
  bool _csvLooksLikeRoster(List<List<String>> rows) {
    if (rows.isEmpty) return false;

    final header = rows.first.join(' ').toLowerCase();
    final allText = rows.map((r) => r.join(' ')).join(' ').toLowerCase();

    // Check for date-related headers
    final hasDateHeaders = RegExp(r'\b(mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\d{1,2}/\d{1,2})\b')
        .hasMatch(header);

    // Check for shift codes in data
    final shiftPattern = RegExp(r'\b(N12|A/L|AD|Tr|Sick|[RDECLNS])\b', caseSensitive: false);
    final hasShiftCodes = shiftPattern.allMatches(allText).length > 10;

    // Check for employee-like first column
    final hasNameColumn = rows.length > 1 &&
        rows.skip(1).every((row) =>
            row.isNotEmpty &&
            row.first.isNotEmpty &&
            !RegExp(r'^\d+$').hasMatch(row.first));

    return (hasDateHeaders || hasShiftCodes) && hasNameColumn;
  }

  /// Parse roster from CSV data
  Roster? _parseRosterFromCsv(List<List<String>> rows) {
    if (rows.length < 2) return null;

    try {
      final header = rows.first;
      final dataRows = rows.skip(1).toList();

      // Try to parse dates from header
      final dates = <DateTime>[];
      final now = DateTime.now();

      for (int i = 1; i < header.length; i++) {
        final cell = header[i].trim();

        // Try various date formats
        DateTime? date = _tryParseDate(cell, now);
        if (date != null) {
          dates.add(date);
        } else {
          // If we can't parse, assume sequential days
          if (dates.isNotEmpty) {
            dates.add(dates.last.add(const Duration(days: 1)));
          } else {
            dates.add(now.add(Duration(days: i - 1)));
          }
        }
      }

      if (dates.isEmpty) return null;

      // Create roster
      final roster = Roster(
        title: 'Imported Roster',
        startDate: dates.first,
        endDate: dates.last,
      );

      // Add employees
      for (final row in dataRows) {
        if (row.isEmpty || row.first.trim().isEmpty) continue;

        final employee = Employee(name: row.first.trim());

        for (int i = 1; i < row.length && i - 1 < dates.length; i++) {
          final shift = row[i].trim().toUpperCase();
          if (shift.isNotEmpty) {
            employee.setShift(dates[i - 1], shift.isEmpty ? 'R' : shift);
          }
        }

        roster.addEmployee(employee);
      }

      return roster.employees.isNotEmpty ? roster : null;
    } catch (e) {
      return null;
    }
  }

  /// Try to parse a date from string
  DateTime? _tryParseDate(String text, DateTime reference) {
    text = text.trim().toLowerCase();

    // Try day/month format (e.g., "15/02", "15-02")
    final dmMatch = RegExp(r'^(\d{1,2})[/\-](\d{1,2})$').firstMatch(text);
    if (dmMatch != null) {
      final day = int.tryParse(dmMatch.group(1)!);
      final month = int.tryParse(dmMatch.group(2)!);
      if (day != null && month != null && day >= 1 && day <= 31 && month >= 1 && month <= 12) {
        return DateTime(reference.year, month, day);
      }
    }

    // Try full date format
    final fullMatch = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})$').firstMatch(text);
    if (fullMatch != null) {
      final day = int.tryParse(fullMatch.group(1)!);
      final month = int.tryParse(fullMatch.group(2)!);
      var year = int.tryParse(fullMatch.group(3)!);
      if (day != null && month != null && year != null) {
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }
    }

    // Try just day number
    final dayOnly = int.tryParse(text);
    if (dayOnly != null && dayOnly >= 1 && dayOnly <= 31) {
      return DateTime(reference.year, reference.month, dayOnly);
    }

    return null;
  }

  /// Detect document type from text lines
  doc.DocumentType _detectTypeFromText(List<String> lines) {
    final allText = lines.join(' ').toLowerCase();

    // Check for roster indicators
    final rosterIndicators = [
      'roster', 'schedule', 'shift', 'rota',
      'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun',
    ];
    final shiftCodePattern = RegExp(r'\b(N12|A/L|AD|Tr|Sick)\b', caseSensitive: false);

    int rosterScore = 0;
    for (final indicator in rosterIndicators) {
      if (allText.contains(indicator)) rosterScore++;
    }
    if (shiftCodePattern.hasMatch(allText)) rosterScore += 3;

    if (rosterScore >= 3) {
      return doc.DocumentType.roster;
    }

    // Default to table for structured data
    return doc.DocumentType.table;
  }

  /// Extract data based on detected type
  Map<String, dynamic> _extractDataFromText(
    List<String> lines,
    List<doc.TextBlock> blocks,
  ) {
    return {
      'lineCount': lines.length,
      'blockCount': blocks.length,
      'rawText': lines.take(10).join('\n'),
    };
  }
}
