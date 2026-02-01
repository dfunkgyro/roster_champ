import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Represents a generic data table extracted from an image
class ExtractedDataTable {
  final String id;
  String title;
  final List<String> headers;
  final List<DataRow> rows;
  DateTime createdAt;
  DateTime updatedAt;

  ExtractedDataTable({
    String? id,
    this.title = 'Extracted Table',
    List<String>? headers,
    List<DataRow>? rows,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        headers = headers ?? [],
        rows = rows ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Number of columns
  int get columnCount => headers.length;

  /// Number of rows (excluding header)
  int get rowCount => rows.length;

  /// Add a new column
  void addColumn(String header, {String defaultValue = ''}) {
    headers.add(header);
    for (final row in rows) {
      row.cells.add(DataCell(value: defaultValue));
    }
    updatedAt = DateTime.now();
  }

  /// Add a new row
  void addRow(List<String> values) {
    final cells = values.map((v) => DataCell(value: v)).toList();
    // Pad with empty cells if needed
    while (cells.length < headers.length) {
      cells.add(DataCell(value: ''));
    }
    rows.add(DataRow(cells: cells));
    updatedAt = DateTime.now();
  }

  /// Remove a row by index
  void removeRow(int index) {
    if (index >= 0 && index < rows.length) {
      rows.removeAt(index);
      updatedAt = DateTime.now();
    }
  }

  /// Remove a column by index
  void removeColumn(int index) {
    if (index >= 0 && index < headers.length) {
      headers.removeAt(index);
      for (final row in rows) {
        if (index < row.cells.length) {
          row.cells.removeAt(index);
        }
      }
      updatedAt = DateTime.now();
    }
  }

  /// Update cell value
  void updateCell(int rowIndex, int colIndex, String value) {
    if (rowIndex >= 0 &&
        rowIndex < rows.length &&
        colIndex >= 0 &&
        colIndex < rows[rowIndex].cells.length) {
      rows[rowIndex].cells[colIndex].value = value;
      updatedAt = DateTime.now();
    }
  }

  /// Get cell value
  String? getCell(int rowIndex, int colIndex) {
    if (rowIndex >= 0 &&
        rowIndex < rows.length &&
        colIndex >= 0 &&
        colIndex < rows[rowIndex].cells.length) {
      return rows[rowIndex].cells[colIndex].value;
    }
    return null;
  }

  /// Convert to 2D list
  List<List<String>> toList({bool includeHeaders = true}) {
    final result = <List<String>>[];
    if (includeHeaders) {
      result.add(List.from(headers));
    }
    for (final row in rows) {
      result.add(row.cells.map((c) => c.value).toList());
    }
    return result;
  }

  /// Convert to CSV string
  String toCsv() {
    final lines = <String>[];
    lines.add(headers.map(_escapeCsvField).join(','));
    for (final row in rows) {
      lines.add(row.cells.map((c) => _escapeCsvField(c.value)).join(','));
    }
    return lines.join('\n');
  }

  String _escapeCsvField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'headers': headers,
      'rows': rows.map((r) => r.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory ExtractedDataTable.fromJson(Map<String, dynamic> json) {
    return ExtractedDataTable(
      id: json['id'] as String?,
      title: json['title'] as String? ?? 'Extracted Table',
      headers: (json['headers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      rows: (json['rows'] as List<dynamic>?)
              ?.map((e) => DataRow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  /// Create from 2D list
  factory ExtractedDataTable.fromList(
    List<List<String>> data, {
    bool firstRowIsHeader = true,
  }) {
    if (data.isEmpty) {
      return ExtractedDataTable();
    }

    final headers = firstRowIsHeader
        ? data.first
        : List.generate(data.first.length, (i) => 'Column ${i + 1}');

    final dataRows = firstRowIsHeader ? data.skip(1) : data;

    return ExtractedDataTable(
      headers: headers,
      rows: dataRows
          .map((row) => DataRow(
                cells: row.map((cell) => DataCell(value: cell)).toList(),
              ))
          .toList(),
    );
  }

  /// Export to JSON string
  String toJsonString() => jsonEncode(toJson());
}

/// Represents a row in the data table
class DataRow {
  final String id;
  final List<DataCell> cells;

  DataRow({
    String? id,
    List<DataCell>? cells,
  })  : id = id ?? const Uuid().v4(),
        cells = cells ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cells': cells.map((c) => c.toJson()).toList(),
    };
  }

  factory DataRow.fromJson(Map<String, dynamic> json) {
    return DataRow(
      id: json['id'] as String?,
      cells: (json['cells'] as List<dynamic>?)
              ?.map((e) => DataCell.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Represents a cell in the data table
class DataCell {
  String value;
  String? note;

  DataCell({
    this.value = '',
    this.note,
  });

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      if (note != null) 'note': note,
    };
  }

  factory DataCell.fromJson(Map<String, dynamic> json) {
    return DataCell(
      value: json['value'] as String? ?? '',
      note: json['note'] as String?,
    );
  }
}
