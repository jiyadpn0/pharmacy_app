import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Shows a custom Material Date Picker dialog that includes a "Today" button
/// in the left header panel (blank area below "Select date").
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
  String? helpText,
  String? cancelText,
  String? confirmText,
  Locale? locale,
}) async {
  return showDialog<DateTime>(
    context: context,
    builder: (BuildContext context) {
      return AppDatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        currentDate: currentDate ?? DateTime.now(),
        initialEntryMode: initialEntryMode,
        initialCalendarMode: initialDatePickerMode,
        helpText: helpText ?? "Select date",
        cancelText: cancelText ?? "Cancel",
        confirmText: confirmText ?? "OK",
      );
    },
  );
}

class AppDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final DatePickerEntryMode initialEntryMode;
  final DatePickerMode initialCalendarMode;
  final String helpText;
  final String cancelText;
  final String confirmText;

  const AppDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    this.initialEntryMode = DatePickerEntryMode.calendar,
    this.initialCalendarMode = DatePickerMode.day,
    this.helpText = "Select date",
    this.cancelText = "Cancel",
    this.confirmText = "OK",
  });

  @override
  State<AppDatePickerDialog> createState() => _AppDatePickerDialogState();
}

class _AppDatePickerDialogState extends State<AppDatePickerDialog> {
  late DateTime _selectedDate;
  late DatePickerEntryMode _entryMode;
  late DatePickerMode _calendarMode;
  late TextEditingController _textController;
  String? _errorText;
  int _calendarKeyCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _entryMode = widget.initialEntryMode;
    _calendarMode = widget.initialCalendarMode;
    _textController = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(_selectedDate),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  DateTime get _todayClamped {
    final now = widget.currentDate;
    final today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(widget.firstDate)) return widget.firstDate;
    if (today.isAfter(widget.lastDate)) return widget.lastDate;
    return today;
  }

  void _selectToday() {
    final today = _todayClamped;
    setState(() {
      _selectedDate = today;
      _textController.text = DateFormat('dd/MM/yyyy').format(today);
      _errorText = null;
      _calendarKeyCount++;
    });
  }

  void _toggleEntryMode() {
    setState(() {
      if (_entryMode == DatePickerEntryMode.calendar) {
        _entryMode = DatePickerEntryMode.input;
        _textController.text = DateFormat('dd/MM/yyyy').format(_selectedDate);
      } else {
        _entryMode = DatePickerEntryMode.calendar;
      }
    });
  }

  void _parseAndSubmitInput() {
    final input = _textController.text.trim();
    try {
      final parts = input.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        final parsed = DateTime(year, month, day);
        if (parsed.isBefore(widget.firstDate) || parsed.isAfter(widget.lastDate)) {
          setState(() => _errorText = "Date out of allowed range");
          return;
        }
        Navigator.pop(context, parsed);
        return;
      }
    } catch (_) {}
    setState(() => _errorText = "Invalid format (dd/MM/yyyy)");
  }

  void _submit() {
    if (_entryMode == DatePickerEntryMode.input) {
      _parseAndSubmitInput();
    } else {
      Navigator.pop(context, _selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > 600;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _submit();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context, null);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: isLandscape ? 540 : 330,
          height: isLandscape ? 400 : 520,
          color: theme.colorScheme.surface,
          child: isLandscape ? _buildLandscapeLayout(theme) : _buildPortraitLayout(theme),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(ThemeData theme) {
    return Row(
      children: [
        // Left Header Panel
        Container(
          width: 190,
          padding: const EdgeInsets.all(20),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.helpText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                DateFormat('EEE,\nMMM d').format(_selectedDate),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.15,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              // "Today" option in the big white/blank area
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _selectToday,
                  icon: const Icon(Icons.today_rounded, size: 18),
                  label: const Text(
                    "Today",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _toggleEntryMode,
                icon: Icon(
                  _entryMode == DatePickerEntryMode.calendar
                      ? Icons.edit_outlined
                      : Icons.calendar_today_outlined,
                ),
                tooltip: _entryMode == DatePickerEntryMode.calendar
                    ? "Enter date"
                    : "Select date",
              ),
            ],
          ),
        ),
        // Right Body & Actions
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildBody(theme)),
              _buildActions(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(ThemeData theme) {
    return Column(
      children: [
        // Top Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.helpText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _selectToday,
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text("Today", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _toggleEntryMode,
                icon: Icon(
                  _entryMode == DatePickerEntryMode.calendar
                      ? Icons.edit_outlined
                      : Icons.calendar_today_outlined,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(theme)),
        _buildActions(theme),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_entryMode == DatePickerEntryMode.input) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: "Date (dd/mm/yyyy)",
                hintText: "dd/mm/yyyy",
                errorText: _errorText,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
              keyboardType: TextInputType.datetime,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      );
    }

    return CalendarDatePicker(
      key: ValueKey('calendar-$_calendarKeyCount'),
      initialDate: _selectedDate,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      currentDate: widget.currentDate,
      initialCalendarMode: _calendarMode,
      onDateChanged: (DateTime date) {
        setState(() {
          _selectedDate = date;
          _textController.text = DateFormat('dd/MM/yyyy').format(date);
        });
      },
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(widget.cancelText),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _submit,
            child: Text(widget.confirmText, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
