import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/document_analyzer_service.dart';
import '../services/file_processor_service.dart';
import '../services/roster_service.dart';
import '../models/document_type.dart';
import 'analysis_screen.dart';
import 'roster_screen.dart';
import 'table_screen.dart';
import 'saved_documents_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  late FileProcessorService _fileProcessor;
  bool _isLoading = false;
  String _loadingMessage = 'Processing...';

  @override
  void initState() {
    super.initState();
    _fileProcessor = FileProcessorService(
      context.read<DocumentAnalyzerService>(),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 90,
      );

      if (image != null) {
        _processFile(File(image.path));
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        _processFile(file);
      }
    } catch (e) {
      _showError('Failed to pick file: $e');
    }
  }

  Future<void> _processFile(File file) async {
    final fileType = _fileProcessor.getFileType(file.path);

    setState(() {
      _isLoading = true;
      _loadingMessage = _getLoadingMessage(fileType);
    });

    try {
      final result = await _fileProcessor.processFile(file);

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (!result.isSuccessful) {
        _showError(result.errorMessage ?? 'Processing failed');
        return;
      }

      // Navigate based on result
      _navigateToResult(result, file);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Processing failed: $e');
    }
  }

  String _getLoadingMessage(FileType fileType) {
    switch (fileType) {
      case FileType.image:
        return 'Analyzing image...\nExtracting text with OCR';
      case FileType.pdf:
        return 'Processing PDF...\nConverting pages and extracting text';
      case FileType.csv:
        return 'Parsing CSV...\nImporting data';
      case FileType.unknown:
        return 'Processing file...';
    }
  }

  void _navigateToResult(FileProcessingResult result, File originalFile) {
    // If we got a roster directly (from CSV)
    if (result.roster != null) {
      final rosterService = context.read<RosterService>();
      rosterService.setCurrentRoster(result.roster!);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RosterScreen(),
        ),
      );
      return;
    }

    // If we got a data table directly (from CSV)
    if (result.dataTable != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TableScreen(table: result.dataTable!),
        ),
      );
      return;
    }

    // Otherwise, go to analysis screen
    if (result.analysisResult != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AnalysisScreen(
            imageFile: result.processedImageFile ?? originalFile,
            analysisResult: result.analysisResult!,
          ),
        ),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showFileSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select File Source',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF003366),
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Camera'),
                subtitle: const Text('Take a photo of your document'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF003366),
                  child: Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('Photo Gallery'),
                subtitle: const Text('Select image from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF003366),
                  child: Icon(Icons.folder_open, color: Colors.white),
                ),
                title: const Text('Browse Files'),
                subtitle: const Text('Select JPG, PNG, PDF, or CSV file'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PicTab'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Saved Documents',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SavedDocumentsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    _loadingMessage,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.document_scanner,
                            size: 80,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Upload a File',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'PicTab will analyze your file and convert it into an interactive digital format',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _showFileSourceDialog,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Select File'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Supported file formats
                  const Text(
                    'Supported File Formats',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildFileFormatCard(
                    icon: Icons.image,
                    title: 'Images (JPG, PNG)',
                    description: 'Photos of rosters, tables, or documents - analyzed with OCR',
                    color: Colors.blue,
                  ),
                  _buildFileFormatCard(
                    icon: Icons.picture_as_pdf,
                    title: 'PDF Documents',
                    description: 'PDF files - pages converted to images then analyzed',
                    color: Colors.red,
                  ),
                  _buildFileFormatCard(
                    icon: Icons.table_chart,
                    title: 'CSV Files',
                    description: 'Spreadsheet data - directly imported without OCR',
                    color: Colors.green,
                  ),

                  const SizedBox(height: 24),

                  // Supported document types
                  const Text(
                    'Recognized Document Types',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildDocumentTypeCard(
                    icon: Icons.calendar_month,
                    title: 'Staff Rosters',
                    description:
                        'Work schedules, shift rotas, and employee timetables',
                    color: Colors.blue,
                  ),
                  _buildDocumentTypeCard(
                    icon: Icons.table_chart,
                    title: 'Data Tables',
                    description:
                        'Spreadsheets, data grids, and tabular information',
                    color: Colors.green,
                  ),
                  _buildDocumentTypeCard(
                    icon: Icons.receipt_long,
                    title: 'Invoices & Receipts',
                    description: 'Bills, purchase receipts, and financial documents',
                    color: Colors.orange,
                  ),

                  const SizedBox(height: 24),

                  // Quick actions
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickActionCard(
                          icon: Icons.add_box,
                          title: 'New Roster',
                          onTap: () => _createNewRoster(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickActionCard(
                          icon: Icons.history,
                          title: 'Recent',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const SavedDocumentsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFileFormatCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          description,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildDocumentTypeCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(
          description,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _createNewRoster(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _NewRosterDialog(
        onCreated: (roster) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const RosterScreen(),
            ),
          );
        },
      ),
    );
  }
}

class _NewRosterDialog extends StatefulWidget {
  final Function(dynamic roster) onCreated;

  const _NewRosterDialog({required this.onCreated});

  @override
  State<_NewRosterDialog> createState() => _NewRosterDialogState();
}

class _NewRosterDialogState extends State<_NewRosterDialog> {
  final _titleController = TextEditingController(text: 'New Roster');
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (date != null) {
      setState(() {
        if (isStart) {
          _startDate = date;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 30));
          }
        } else {
          _endDate = date;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Roster'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Roster Title',
              hintText: 'Enter a name for this roster',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start Date'),
            subtitle: Text(
              '${_startDate.day}/${_startDate.month}/${_startDate.year}',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () => _selectDate(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('End Date'),
            subtitle: Text(
              '${_endDate.day}/${_endDate.month}/${_endDate.year}',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () => _selectDate(false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final rosterService = context.read<RosterService>();
            final roster = rosterService.createNewRoster(
              title: _titleController.text,
              startDate: _startDate,
              endDate: _endDate,
            );
            Navigator.pop(context);
            widget.onCreated(roster);
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
