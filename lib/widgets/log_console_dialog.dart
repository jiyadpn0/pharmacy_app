import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_logger.dart';

class LogConsoleDialog extends StatefulWidget {
  const LogConsoleDialog({super.key});

  @override
  State<LogConsoleDialog> createState() => _LogConsoleDialogState();
}

class _LogConsoleDialogState extends State<LogConsoleDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _selectedCategory = "ALL";
  bool _autoScroll = true;
  String _searchQuery = "";

  final List<String> _categories = [
    "ALL",
    "ERRORS",
    "SUPABASE",
    "SQLITE",
    "NETWORK",
    "PERFORMANCE",
    "BUSINESS",
    "SYSTEM",
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    AppLogger.instance.addListener(_onNewLogArrived);
  }

  void _onNewLogArrived() {
    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppLogger.instance.removeListener(_onNewLogArrived);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<LogEntry> _getFilteredLogs() {
    final allLogs = AppLogger.instance.logs;
    return allLogs.where((entry) {
      // Category Filter
      if (_selectedCategory == "ERRORS") {
        if (entry.level != LogLevel.error) return false;
      } else if (_selectedCategory != "ALL") {
        if (!entry.category.contains(_selectedCategory)) return false;
      }

      // Search Query Filter
      if (_searchQuery.isNotEmpty) {
        final matchMsg = entry.message.toLowerCase().contains(_searchQuery);
        final matchCat = entry.category.toLowerCase().contains(_searchQuery);
        final matchDet = entry.details?.toLowerCase().contains(_searchQuery) ?? false;
        final matchErr = entry.error?.toLowerCase().contains(_searchQuery) ?? false;
        if (!matchMsg && !matchCat && !matchDet && !matchErr) return false;
      }

      return true;
    }).toList();
  }

  Color _getCategoryColor(LogEntry entry) {
    if (entry.level == LogLevel.error) return const Color(0xFFFF5252);
    if (entry.level == LogLevel.warning) return const Color(0xFFFFC107);

    switch (entry.category) {
      case "SUPABASE":
        return const Color(0xFF00E5FF);
      case "SQLITE":
        return const Color(0xFF64FFDA);
      case "NETWORK":
        return const Color(0xFF69F0AE);
      case "PERFORMANCE":
        return const Color(0xFFE040FB);
      case "PRINTER":
        return const Color(0xFFFF4081);
      case "SYSTEM":
        return const Color(0xFF40C4FF);
      default:
        return const Color(0xFFFF9100);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredLogs();
    final totalLogs = AppLogger.instance.logs.length;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF334155), width: 1.5),
      ),
      child: SizedBox(
        width: 1000,
        height: 700,
        child: Column(
          children: [
            // Header Bar
            _buildHeader(context, filtered.length, totalLogs),
            const Divider(height: 1, color: Color(0xFF334155)),

            // Filter & Search Controls
            _buildControlBar(),
            const Divider(height: 1, color: Color(0xFF334155)),

            // Log Console Body
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _buildLogCard(filtered[index]);
                      },
                    ),
            ),

            // Footer Status Bar
            _buildFooter(filtered),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int filteredCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal_rounded, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 10),
          const Text(
            "SOFTWARE & SUPABASE LOG CONSOLE",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
            ),
            child: Text(
              "$filteredCount / $totalCount logs",
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),

          // Auto Scroll Switch
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Auto-Scroll", style: TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(width: 4),
              SizedBox(
                height: 24,
                child: Switch(
                  value: _autoScroll,
                  activeThumbColor: Colors.cyanAccent,
                  onChanged: (val) {
                    setState(() {
                      _autoScroll = val;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Close Button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: "Close Log Window",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Search Input
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: "Search logs (e.g. 'Entry 21', 'Supabase', 'Error')...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white38, size: 14),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.cyanAccent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Action Buttons
              ElevatedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text("COPY FILTERED", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () async {
                  final filteredLogs = _getFilteredLogs();
                  await AppLogger.instance.copyAllToClipboard(filteredLogs);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Copied ${filteredLogs.length} logs to clipboard! Paste directly into chat."),
                        backgroundColor: Colors.teal,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),

              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt_rounded, size: 14),
                label: const Text("EXPORT FILE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () async {
                  final path = await AppLogger.instance.exportToFile();
                  if (mounted && path != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Exported log file to: $path"),
                        backgroundColor: Colors.indigo,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),

              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                label: const Text("CLEAR", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () {
                  AppLogger.instance.clear();
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.black : Colors.white70,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: cat == "ERRORS" ? Colors.redAccent : Colors.cyanAccent,
                    backgroundColor: const Color(0xFF1E293B),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(
                        color: isSelected
                            ? (cat == "ERRORS" ? Colors.redAccent : Colors.cyanAccent)
                            : const Color(0xFF334155),
                      ),
                    ),
                    onSelected: (val) {
                      setState(() {
                        _selectedCategory = cat;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(LogEntry entry) {
    final catColor = _getCategoryColor(entry);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: entry.level == LogLevel.error
              ? Colors.red.withValues(alpha: 0.6)
              : const Color(0xFF334155),
          width: entry.level == LogLevel.error ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "[${entry.timeFormatted}]",
                style: GoogleFonts.firaCode(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: catColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  entry.category,
                  style: GoogleFonts.firaCode(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: catColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "#${entry.id}",
                style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white24),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 12, color: Colors.white38),
                tooltip: "Copy this log line",
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: EdgeInsets.zero,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: entry.toFullString()));
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            entry.message,
            style: GoogleFonts.firaCode(
              fontSize: 12,
              color: entry.level == LogLevel.error ? const Color(0xFFFF8A80) : Colors.white,
              height: 1.3,
            ),
          ),
          if (entry.details != null && entry.details!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                "Details: ${entry.details}",
                style: GoogleFonts.firaCode(fontSize: 11, color: Colors.cyanAccent.shade100),
              ),
            ),
          ],
          if (entry.error != null && entry.error!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                "Exception: ${entry.error}",
                style: GoogleFonts.firaCode(fontSize: 11, color: Colors.redAccent),
              ),
            ),
          ],
          if (entry.stackTrace != null && entry.stackTrace!.isNotEmpty) ...[
            const SizedBox(height: 4),
            ExpansionTile(
              dense: true,
              tilePadding: EdgeInsets.zero,
              title: Text("Stack Trace", style: GoogleFonts.firaCode(fontSize: 10, color: Colors.amberAccent)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  color: Colors.black45,
                  child: SelectableText(
                    entry.stackTrace!,
                    style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.speaker_notes_off_rounded, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text("No log entries match your current search/filter.", style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _selectedCategory = "ALL";
              });
            },
            child: const Text("Reset Filters", style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(List<LogEntry> filtered) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.white38),
          const SizedBox(width: 6),
          const Text(
            "Tip: Click 'COPY FILTERED' to paste complete raw diagnostic logs into chat.",
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const Spacer(),
          Text(
            "Auto-Purges at 5,000 entries",
            style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: GoogleFonts.firaCode().fontFamily),
          ),
        ],
      ),
    );
  }
}
