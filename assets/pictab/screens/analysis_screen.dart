import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/document_type.dart';
import '../models/roster.dart';
import '../models/data_table.dart';
import '../services/document_analyzer_service.dart';
import '../services/roster_service.dart';
import 'roster_screen.dart';
import 'table_screen.dart';

class AnalysisScreen extends StatefulWidget {
  final File imageFile;
  final DocumentAnalysisResult analysisResult;

  const AnalysisScreen({
    super.key,
    required this.imageFile,
    required this.analysisResult,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _showRawText = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.analysisResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Results'),
        actions: [
          IconButton(
            icon: Icon(_showRawText ? Icons.visibility_off : Icons.visibility),
            tooltip: _showRawText ? 'Hide raw text' : 'Show raw text',
            onPressed: () => setState(() => _showRawText = !_showRawText),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image preview
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.file(
                      widget.imageFile,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.image, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.imageFile.path.split('/').last,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Document type card
            _buildDocumentTypeCard(result),

            const SizedBox(height: 16),

            // Confidence indicator
            _buildConfidenceCard(result),

            const SizedBox(height: 16),

            // Extracted data preview
            _buildExtractedDataCard(result),

            if (_showRawText) ...[
              const SizedBox(height: 16),
              _buildRawTextCard(result),
            ],

            const SizedBox(height: 24),

            // Action buttons
            if (result.isSuccessful) _buildActionButtons(result),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentTypeCard(DocumentAnalysisResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _getTypeColor(result.type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  result.type.icon,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Document Type',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.type.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.type.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceCard(DocumentAnalysisResult result) {
    final confidence = result.confidence;
    final color = confidence >= 0.7
        ? Colors.green
        : confidence >= 0.4
            ? Colors.orange
            : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Detection Confidence',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '${(confidence * 100).toInt()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: confidence,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getConfidenceDescription(confidence),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedDataCard(DocumentAnalysisResult result) {
    final data = result.extractedData;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.data_object, size: 20),
                SizedBox(width: 8),
                Text(
                  'Extracted Data',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const Divider(),
            if (result.type == DocumentType.roster) ...[
              _buildDataRow('Start Date', data['startDate']?.toString().split('T')[0] ?? 'N/A'),
              _buildDataRow('End Date', data['endDate']?.toString().split('T')[0] ?? 'N/A'),
              _buildDataRow('Employees Found', '${(data['employees'] as List?)?.length ?? 0}'),
              _buildDataRow('Days', '${data['rowCount'] ?? 'N/A'}'),
            ] else if (result.type == DocumentType.table) ...[
              _buildDataRow('Columns', '${data['columnCount'] ?? 0}'),
              _buildDataRow('Rows', '${data['rowCount'] ?? 0}'),
              if (data['headers'] != null)
                _buildDataRow('Headers', (data['headers'] as List).take(3).join(', ') + '...'),
            ] else ...[
              _buildDataRow('Text Lines', '${result.rawTextLines.length}'),
              _buildDataRow('Text Blocks', '${result.textBlocks.length}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildRawTextCard(DocumentAnalysisResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.text_snippet, size: 20),
                SizedBox(width: 8),
                Text(
                  'Raw Extracted Text',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const Divider(),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Text(
                  result.rawTextLines.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(DocumentAnalysisResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => _convertToDigitalFormat(result),
          icon: const Icon(Icons.transform),
          label: Text(_getConvertButtonText(result.type)),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _reanalyzeAsType(result),
          icon: const Icon(Icons.refresh),
          label: const Text('Re-analyze as Different Type'),
        ),
      ],
    );
  }

  Color _getTypeColor(DocumentType type) {
    switch (type) {
      case DocumentType.roster:
        return Colors.blue;
      case DocumentType.table:
        return Colors.green;
      case DocumentType.invoice:
        return Colors.orange;
      case DocumentType.receipt:
        return Colors.purple;
      case DocumentType.form:
        return Colors.teal;
      case DocumentType.unknown:
        return Colors.grey;
    }
  }

  String _getConfidenceDescription(double confidence) {
    if (confidence >= 0.8) {
      return 'High confidence - Document type clearly identified';
    } else if (confidence >= 0.6) {
      return 'Good confidence - Document type likely correct';
    } else if (confidence >= 0.4) {
      return 'Moderate confidence - Please verify document type';
    } else {
      return 'Low confidence - Consider re-analyzing or manual input';
    }
  }

  String _getConvertButtonText(DocumentType type) {
    switch (type) {
      case DocumentType.roster:
        return 'Create Interactive Roster';
      case DocumentType.table:
        return 'Create Editable Table';
      case DocumentType.invoice:
      case DocumentType.receipt:
        return 'Extract Data';
      case DocumentType.form:
        return 'Create Digital Form';
      case DocumentType.unknown:
        return 'View Raw Data';
    }
  }

  void _convertToDigitalFormat(DocumentAnalysisResult result) {
    final analyzer = context.read<DocumentAnalyzerService>();

    switch (result.type) {
      case DocumentType.roster:
        final roster = analyzer.createRosterFromData(result.extractedData);
        if (roster != null) {
          final rosterService = context.read<RosterService>();
          rosterService.setCurrentRoster(roster);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const RosterScreen(),
            ),
          );
        } else {
          _showError('Failed to create roster from extracted data');
        }
        break;

      case DocumentType.table:
        final table = analyzer.createTableFromData(result.extractedData);
        if (table != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => TableScreen(table: table),
            ),
          );
        } else {
          _showError('Failed to create table from extracted data');
        }
        break;

      default:
        _showError('Conversion not yet supported for this document type');
    }
  }

  void _reanalyzeAsType(DocumentAnalysisResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-analyze Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select the correct document type:'),
            const SizedBox(height: 16),
            ...DocumentType.values
                .where((t) => t != DocumentType.unknown)
                .map((type) => ListTile(
                      leading: Text(type.icon, style: const TextStyle(fontSize: 24)),
                      title: Text(type.displayName),
                      onTap: () {
                        Navigator.pop(context);
                        // Re-process with forced type
                        // For now, just show a message
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Re-analyzing as ${type.displayName}...'),
                          ),
                        );
                      },
                    )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
