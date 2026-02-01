/// Enum representing different types of documents that can be recognized
enum DocumentType {
  roster,
  table,
  invoice,
  receipt,
  form,
  unknown,
}

extension DocumentTypeExtension on DocumentType {
  String get displayName {
    switch (this) {
      case DocumentType.roster:
        return 'Staff Roster / Schedule';
      case DocumentType.table:
        return 'Data Table';
      case DocumentType.invoice:
        return 'Invoice';
      case DocumentType.receipt:
        return 'Receipt';
      case DocumentType.form:
        return 'Form';
      case DocumentType.unknown:
        return 'Unknown Document';
    }
  }

  String get description {
    switch (this) {
      case DocumentType.roster:
        return 'A staff work schedule or shift roster with dates and employee assignments';
      case DocumentType.table:
        return 'A structured data table with rows and columns';
      case DocumentType.invoice:
        return 'A billing document with line items and totals';
      case DocumentType.receipt:
        return 'A purchase receipt or transaction record';
      case DocumentType.form:
        return 'A structured form with fields and values';
      case DocumentType.unknown:
        return 'Document type could not be determined';
    }
  }

  String get icon {
    switch (this) {
      case DocumentType.roster:
        return '📅';
      case DocumentType.table:
        return '📊';
      case DocumentType.invoice:
        return '🧾';
      case DocumentType.receipt:
        return '🧾';
      case DocumentType.form:
        return '📝';
      case DocumentType.unknown:
        return '❓';
    }
  }
}

/// Result of document analysis
class DocumentAnalysisResult {
  final DocumentType type;
  final double confidence;
  final Map<String, dynamic> extractedData;
  final List<String> rawTextLines;
  final List<TextBlock> textBlocks;
  final String? errorMessage;

  DocumentAnalysisResult({
    required this.type,
    required this.confidence,
    this.extractedData = const {},
    this.rawTextLines = const [],
    this.textBlocks = const [],
    this.errorMessage,
  });

  bool get isSuccessful => errorMessage == null && type != DocumentType.unknown;

  factory DocumentAnalysisResult.error(String message) {
    return DocumentAnalysisResult(
      type: DocumentType.unknown,
      confidence: 0.0,
      errorMessage: message,
    );
  }
}

/// Represents a block of text found in the image
class TextBlock {
  final String text;
  final Rect boundingBox;
  final List<TextLine> lines;

  TextBlock({
    required this.text,
    required this.boundingBox,
    this.lines = const [],
  });
}

/// Represents a line of text within a block
class TextLine {
  final String text;
  final Rect boundingBox;

  TextLine({
    required this.text,
    required this.boundingBox,
  });
}

/// Bounding box for text elements
class Rect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  Rect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
}
