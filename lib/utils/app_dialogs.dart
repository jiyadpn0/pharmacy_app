import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import 'app_sounds.dart';

class PathLinkWidget extends StatefulWidget {
  final String path;
  final String? message;

  const PathLinkWidget({
    super.key,
    required this.path,
    this.message,
  });

  @override
  State<PathLinkWidget> createState() => _PathLinkWidgetState();
}

class _PathLinkWidgetState extends State<PathLinkWidget> {
  bool _copied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.path));
    setState(() => _copied = true);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Link / Path copied to clipboard:\n${widget.path}",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.teal.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2638) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.message != null && widget.message!.isNotEmpty) ...[
            Text(
              widget.message!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 10),
          ],
          SelectableText(
            widget.path,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: isDark ? Colors.cyan.shade300 : Colors.indigo.shade900,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _copyToClipboard,
              icon: Icon(
                _copied ? Icons.check_circle_rounded : Icons.link_rounded,
                size: 16,
              ),
              label: Text(
                _copied ? "LINK COPIED TO CLIPBOARD!" : "COPY LINK / PATH",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _copied ? Colors.teal : Colors.indigo.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PathLinkDialog extends StatefulWidget {
  final String title;
  final String message;
  final String path;
  final IconData icon;
  final Color iconColor;

  const PathLinkDialog({
    super.key,
    required this.title,
    required this.message,
    required this.path,
    this.icon = Icons.check_circle,
    this.iconColor = Colors.teal,
  });

  @override
  State<PathLinkDialog> createState() => _PathLinkDialogState();
}

class _PathLinkDialogState extends State<PathLinkDialog> {
  bool _copied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.path));
    setState(() => _copied = true);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Link / Path copied to clipboard:\n${widget.path}",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.teal.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(widget.icon, color: widget.iconColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: PathLinkWidget(
          message: widget.message,
          path: widget.path,
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _copyToClipboard,
          icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
          label: Text(_copied ? "COPIED" : "COPY LINK"),
          style: OutlinedButton.styleFrom(
            foregroundColor: _copied ? Colors.teal : Colors.indigo,
            side: BorderSide(color: _copied ? Colors.teal : Colors.indigo),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.iconColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class AppDialogs {
  // ---> THE FIX: The Global Exception Cleaner <---
  static String _cleanErrorMessage(String msg) {
    String clean = msg;
    
    // 1. Remove the standard Exception prefix
    clean = clean.replaceAll('Exception: ', '');
    
    // 2. Hide raw SQL queries if a database crash happens
    if (clean.contains('Causing statement:')) {
      clean = clean.split('Causing statement:').first;
    }
    
    // 3. Strip out ugly SQLite database tags
    clean = clean.replaceAll(RegExp(r'SqfliteFfiException\(.*?\)[:]?', caseSensitive: false, dotAll: true), '');
    clean = clean.replaceAll(RegExp(r'DatabaseException\(.*?\)[:]?', caseSensitive: false, dotAll: true), '');
    clean = clean.replaceAll(RegExp(r'SqliteException\(\d+\):', caseSensitive: false), '');
    clean = clean.replaceAll('SQL logic error (code 1)', '');
    clean = clean.replaceAll('while preparing statement,', '');
    
    // 4. Return the clean, human-readable string
    return clean.trim();
  }

  static Map<String, String>? _extractPathAndMessage(String content) {
    final pathRegex = RegExp(
      r'([a-zA-Z]:[\\/][^\n\r]+|/[^\n\r]+\.[a-zA-Z0-9]+|\.[\\/][^\n\r]+)',
      caseSensitive: false,
    );
    final match = pathRegex.firstMatch(content);
    if (match == null) return null;

    final path = match.group(0)!.trim();
    if (!path.contains('\\') && !path.contains('/')) return null;

    final message = content.replaceFirst(path, '').trim();
    return {
      'message': message,
      'path': path,
    };
  }

  static void showPathDialog({
    required BuildContext context,
    required String title,
    required String message,
    required String path,
    IconData icon = Icons.check_circle,
    Color iconColor = Colors.teal,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(ctx);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: PathLinkDialog(
          title: title,
          message: message,
          path: path,
          icon: icon,
          iconColor: iconColor,
        ),
      ),
    );
  }

  static void showLoadingDialog(BuildContext context, {String message = "Processing..."}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            try {
              Provider.of<PharmacyProvider>(context, listen: false).cancelImport();
            } catch (_) {}
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  const Text("Press ESC to cancel / go back", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void showFastDialog({
    required BuildContext context,
    required String title,
    required String content,
    bool isSuccess = false,
  }) {
    if (!isSuccess) AppSounds.playError();
    
    final cleanContent = _cleanErrorMessage(content);
    final pathData = _extractPathAndMessage(cleanContent);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(ctx);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Text(isSuccess ? "✅" : "⚠️"),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: pathData != null
              ? SizedBox(
                  width: 500,
                  child: PathLinkWidget(
                    message: pathData['message'],
                    path: pathData['path']!,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isSuccess ? "✨" : "❌", style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(cleanContent, style: const TextStyle(fontSize: 14))),
                  ],
                ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSuccess ? Colors.green : Colors.blueGrey.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text("OK (ENTER/ESC)", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    String yesLabel = "YES",
    String noLabel = "NO",
    bool isDangerous = false,
  }) {
    AppSounds.playError();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              Navigator.pop(ctx, true);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(ctx, false);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: Row(
            children: [
              const Text("⚠️"),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("❓", style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(content)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("$noLabel (ESC)", style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDangerous ? Colors.red : Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text("$yesLabel (ENTER)", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
