import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Shows a compact, distraction-free desktop dropdown calendar right below
/// the triggering date field (matching classic Windows ERP / Photo 1).
///
/// Clicking anywhere outside the calendar closes it immediately with last saved
/// date (no edits applied, returns null).
/// Clicking any date or "Today" instantly selects it with smooth feedback and closes.
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
  Rect? targetRect,
  Offset? targetOffset,
}) async {
  final rect = _resolveTargetRect(context, explicitRect: targetRect, explicitOffset: targetOffset);

  return Navigator.of(context, rootNavigator: true).push<DateTime>(
    DesktopCalendarPopupRoute(
      sourceContext: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      currentDate: currentDate ?? DateTime.now(),
      targetRect: rect,
    ),
  );
}

Rect? _resolveTargetRect(BuildContext context, {Rect? explicitRect, Offset? explicitOffset}) {
  if (explicitRect != null) return explicitRect;
  if (explicitOffset != null) return explicitOffset & const Size(120, 28);

  try {
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize && ro.size.width > 0 && ro.size.height > 0) {
      final media = MediaQuery.maybeOf(context);
      final maxW = (media?.size.width ?? 1200) * 0.75;
      final maxH = (media?.size.height ?? 900) * 0.75;
      if (ro.size.width < maxW && ro.size.height < maxH) {
        final offset = ro.localToGlobal(Offset.zero);
        return offset & ro.size;
      }
    }
  } catch (_) {}

  try {
    final focusedRo = FocusManager.instance.primaryFocus?.context?.findRenderObject();
    if (focusedRo is RenderBox && focusedRo.hasSize && focusedRo.size.width > 0 && focusedRo.size.height > 0) {
      final offset = focusedRo.localToGlobal(Offset.zero);
      return offset & focusedRo.size;
    }
  } catch (_) {}

  return null;
}

/// Custom lightweight popup route that displays the calendar dropdown anchored
/// to the target field without any modal dimming barrier (barrierColor is transparent).
/// Clicking outside triggers dismiss and pops null without altering any state.
class DesktopCalendarPopupRoute extends PopupRoute<DateTime> {
  final BuildContext sourceContext;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final Rect? targetRect;

  DesktopCalendarPopupRoute({
    required this.sourceContext,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    this.targetRect,
  });

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => 'Close Calendar';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 90);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        const double popupWidth = 186.0;
        const double popupHeight = 178.0;

        double left = (screenSize.width - popupWidth) / 2;
        double top = (screenSize.height - popupHeight) / 3;

        if (targetRect != null) {
          left = targetRect!.left;
          top = targetRect!.bottom + 1.0;

          // Adjust horizontally to stay comfortably on screen
          if (left + popupWidth > screenSize.width - 8) {
            left = screenSize.width - popupWidth - 8;
          }
          if (left < 8) left = 8;

          // Adjust vertically if overflowing bottom of screen
          if (top + popupHeight > screenSize.height - 8) {
            if (targetRect!.top - popupHeight - 2 >= 8) {
              top = targetRect!.top - popupHeight - 2;
            } else {
              top = (screenSize.height - popupHeight - 8).clamp(8.0, double.infinity);
            }
          }
        }

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                ),
                child: FadeTransition(
                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  child: DesktopCalendarDropdown(
                    initialDate: initialDate,
                    firstDate: firstDate,
                    lastDate: lastDate,
                    currentDate: currentDate,
                    onDateSelected: (date) {
                      Navigator.of(context).pop(date);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Compact Windows-style desktop calendar dropdown widget with smooth moving and selection animations.
class DesktopCalendarDropdown extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final ValueChanged<DateTime> onDateSelected;

  const DesktopCalendarDropdown({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.onDateSelected,
  });

  @override
  State<DesktopCalendarDropdown> createState() => _DesktopCalendarDropdownState();
}

enum _CalendarViewMode { days, months, years }

class _DesktopCalendarDropdownState extends State<DesktopCalendarDropdown> {
  late int _displayedYear;
  late int _displayedMonth;
  late DateTime _selectedDate;
  _CalendarViewMode _viewMode = _CalendarViewMode.days;
  bool _isMovingForward = true;

  DateTime? _animatingSelectedDate;
  int? _animatingSelectedMonth;
  int? _animatingSelectedYear;
  bool _animatingToday = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _displayedYear = widget.initialDate.year;
    _displayedMonth = widget.initialDate.month;
  }

  void _prev() {
    setState(() {
      _isMovingForward = false;
      switch (_viewMode) {
        case _CalendarViewMode.days:
          if (_displayedMonth == 1) {
            _displayedMonth = 12;
            _displayedYear--;
          } else {
            _displayedMonth--;
          }
          break;
        case _CalendarViewMode.months:
          _displayedYear--;
          break;
        case _CalendarViewMode.years:
          _displayedYear -= 10;
          break;
      }
    });
  }

  void _next() {
    setState(() {
      _isMovingForward = true;
      switch (_viewMode) {
        case _CalendarViewMode.days:
          if (_displayedMonth == 12) {
            _displayedMonth = 1;
            _displayedYear++;
          } else {
            _displayedMonth++;
          }
          break;
        case _CalendarViewMode.months:
          _displayedYear++;
          break;
        case _CalendarViewMode.years:
          _displayedYear += 10;
          break;
      }
    });
  }

  void _changeSelectedDate(int dayDelta) {
    setState(() {
      final newDate = _selectedDate.add(Duration(days: dayDelta));
      if (newDate.isBefore(widget.firstDate) || newDate.isAfter(widget.lastDate)) return;
      _selectedDate = newDate;
      _displayedYear = newDate.year;
      _displayedMonth = newDate.month;
    });
  }

  void _onDaySelected(DateTime cellDate) async {
    setState(() {
      _selectedDate = cellDate;
      _animatingSelectedDate = cellDate;
    });
    // Brief tactile micro-bounce and highlight animation
    await Future.delayed(const Duration(milliseconds: 85));
    if (mounted) {
      widget.onDateSelected(cellDate);
    }
  }

  void _onMonthSelected(int monthIdx) async {
    setState(() {
      _animatingSelectedMonth = monthIdx;
      _displayedMonth = monthIdx;
    });
    await Future.delayed(const Duration(milliseconds: 70));
    if (mounted) {
      setState(() {
        _animatingSelectedMonth = null;
        _isMovingForward = true;
        _viewMode = _CalendarViewMode.days;
      });
    }
  }

  void _onYearSelected(int year) async {
    setState(() {
      _animatingSelectedYear = year;
      _displayedYear = year;
    });
    await Future.delayed(const Duration(milliseconds: 70));
    if (mounted) {
      setState(() {
        _animatingSelectedYear = null;
        _isMovingForward = true;
        _viewMode = _CalendarViewMode.months;
      });
    }
  }

  void _onTodaySelected() async {
    final now = widget.currentDate;
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _animatingToday = true;
      _selectedDate = today;
      _displayedYear = today.year;
      _displayedMonth = today.month;
      _viewMode = _CalendarViewMode.days;
    });
    await Future.delayed(const Duration(milliseconds: 85));
    if (mounted) {
      widget.onDateSelected(today);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF252526) : Colors.white;
    final borderColor = isDark ? const Color(0xFF4B4B4B) : const Color(0xFF7F9DB9);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop(null);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            widget.onDateSelected(_selectedDate);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _changeSelectedDate(-1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _changeSelectedDate(1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _changeSelectedDate(-7);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _changeSelectedDate(7);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
            _prev();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
            _next();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 186,
          height: 178,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: 1),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(2, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            children: [
              // HEADER ROW: <  Animated Title  >
              SizedBox(
                height: 22,
                child: Row(
                  children: [
                    InkWell(
                      onTap: _prev,
                      hoverColor: isDark ? Colors.white12 : const Color(0xFFE5F1FB),
                      borderRadius: BorderRadius.circular(2),
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        child: Icon(Icons.arrow_left_rounded, size: 20, color: textColor),
                      ),
                    ),
                    _buildHeaderTitle(isDark, textColor),
                    InkWell(
                      onTap: _next,
                      hoverColor: isDark ? Colors.white12 : const Color(0xFFE5F1FB),
                      borderRadius: BorderRadius.circular(2),
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        child: Icon(Icons.arrow_right_rounded, size: 20, color: textColor),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 1),

              // MAIN BODY: DAY GRID, MONTH GRID, OR YEAR GRID WITH SMOOTH SLIDE TRANSITION
              Expanded(
                child: _buildBody(isDark),
              ),

              // BOTTOM DIVIDER & "Today: dd/MM/yyyy" BAR
              Container(
                height: 1,
                color: isDark ? Colors.white12 : const Color(0xFFE0E0E0),
                margin: const EdgeInsets.symmetric(vertical: 1),
              ),
              InkWell(
                onTap: _onTodaySelected,
                hoverColor: isDark ? Colors.white12 : const Color(0xFFE5F1FB),
                borderRadius: BorderRadius.circular(2),
                child: AnimatedScale(
                  scale: _animatingToday ? 0.93 : 1.0,
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.easeOutCubic,
                  child: SizedBox(
                    height: 19,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 14,
                          height: 10,
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF3399FF), width: 1.1),
                            borderRadius: BorderRadius.circular(1),
                            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          ),
                          alignment: Alignment.topCenter,
                          child: Container(
                            height: 2.5,
                            color: const Color(0xFF3399FF),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          "Today: ${DateFormat('dd/MM/yyyy').format(widget.currentDate)}",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderTitle(bool isDark, Color textColor) {
    if (_viewMode == _CalendarViewMode.days) {
      final monthName = DateFormat('MMMM').format(DateTime(_displayedYear, _displayedMonth, 1));
      return Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAnimatedHeaderButton(
              text: monthName,
              onTap: () => setState(() => _viewMode = _CalendarViewMode.months),
              isDark: isDark,
            ),
            Text(
              ", ",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF003366),
              ),
            ),
            _buildAnimatedHeaderButton(
              text: "$_displayedYear",
              onTap: () => setState(() => _viewMode = _CalendarViewMode.years),
              isDark: isDark,
            ),
          ],
        ),
      );
    } else if (_viewMode == _CalendarViewMode.months) {
      return Expanded(
        child: Center(
          child: _buildAnimatedHeaderButton(
            text: "$_displayedYear",
            onTap: () => setState(() => _viewMode = _CalendarViewMode.years),
            isDark: isDark,
          ),
        ),
      );
    } else {
      final startYear = (_displayedYear ~/ 10) * 10;
      return Expanded(
        child: Center(
          child: _buildAnimatedHeaderButton(
            text: "$startYear - ${startYear + 11}",
            onTap: () => setState(() => _viewMode = _CalendarViewMode.months),
            isDark: isDark,
          ),
        ),
      );
    }
  }

  Widget _buildAnimatedHeaderButton({
    required String text,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      hoverColor: isDark ? Colors.white12 : const Color(0xFFE5F1FB),
      borderRadius: BorderRadius.circular(2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
          child: Text(
            text,
            key: ValueKey(text),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF003366),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final inOffset = _isMovingForward ? const Offset(0.25, 0.0) : const Offset(-0.25, 0.0);
          final outOffset = _isMovingForward ? const Offset(-0.25, 0.0) : const Offset(0.25, 0.0);

          if (anim.status == AnimationStatus.forward || anim.status == AnimationStatus.completed) {
            return SlideTransition(
              position: Tween<Offset>(begin: inOffset, end: Offset.zero).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            );
          } else {
            return SlideTransition(
              position: Tween<Offset>(begin: Offset.zero, end: outOffset).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            );
          }
        },
        child: KeyedSubtree(
          key: ValueKey('${_viewMode.name}_${_displayedYear}_$_displayedMonth'),
          child: _buildCurrentView(isDark),
        ),
      ),
    );
  }

  Widget _buildCurrentView(bool isDark) {
    switch (_viewMode) {
      case _CalendarViewMode.days:
        return _buildDayGrid(isDark);
      case _CalendarViewMode.months:
        return _buildMonthGrid(isDark);
      case _CalendarViewMode.years:
        return _buildYearGrid(isDark);
    }
  }

  Widget _buildYearGrid(bool isDark) {
    final startYear = (_displayedYear ~/ 10) * 10;

    return Column(
      children: List.generate(4, (r) {
        return Expanded(
          child: Row(
            children: List.generate(3, (c) {
              final year = startYear + (r * 3 + c);
              final isSelected = year == _selectedDate.year;
              final isCurrentDisplayed = year == _displayedYear;
              final isBeingSelected = _animatingSelectedYear == year;

              return Expanded(
                child: InkWell(
                  onTap: () => _onYearSelected(year),
                  hoverColor: isDark ? Colors.white12 : const Color(0xFFE5F1FB),
                  borderRadius: BorderRadius.circular(2),
                  child: AnimatedScale(
                    scale: isBeingSelected ? 0.91 : 1.0,
                    duration: const Duration(milliseconds: 70),
                    curve: Curves.easeOutCubic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark ? Colors.blue.withValues(alpha: 0.35) : const Color(0xFFD6E8FF))
                            : (isCurrentDisplayed && !isSelected
                                ? (isDark ? Colors.blue.withValues(alpha: 0.15) : const Color(0xFFEBF3FB))
                                : Colors.transparent),
                        border: isSelected
                            ? Border.all(color: const Color(0xFF3399FF), width: 1.2)
                            : (isCurrentDisplayed
                                ? Border.all(color: const Color(0xFF99CCFF), width: 0.8)
                                : null),
                        borderRadius: BorderRadius.circular(isBeingSelected ? 3 : 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "$year",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: (isSelected || isCurrentDisplayed) ? FontWeight.bold : FontWeight.normal,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildDayGrid(bool isDark) {
    final firstDayOfMonth = DateTime(_displayedYear, _displayedMonth, 1);
    final weekday = firstDayOfMonth.weekday; // 1=Mon .. 7=Sun
    final firstDayCol = weekday % 7; // 0=Sun .. 6=Sat

    // Fixed 6-row 42-cell grid (matches Windows MonthCalendar & Photo 1)
    int leadingDays = firstDayCol;
    if (leadingDays == 0) {
      leadingDays = 7;
    }

    final lastDayOfPrevMonth = DateTime(_displayedYear, _displayedMonth, 0);
    final daysInPrevMonth = lastDayOfPrevMonth.day;
    final lastDayOfCurrentMonth = DateTime(_displayedYear, _displayedMonth + 1, 0);
    final daysInCurrentMonth = lastDayOfCurrentMonth.day;

    final now = widget.currentDate;

    return Column(
      children: [
        // WEEKDAY HEADER ROW
        const SizedBox(
          height: 15,
          child: Row(
            children: [
              _WeekdayHeader("Sun"),
              _WeekdayHeader("Mon"),
              _WeekdayHeader("Tue"),
              _WeekdayHeader("Wed"),
              _WeekdayHeader("Thu"),
              _WeekdayHeader("Fri"),
              _WeekdayHeader("Sat"),
            ],
          ),
        ),
        Container(
          height: 1,
          color: isDark ? Colors.white10 : const Color(0xFFF0F0F0),
          margin: const EdgeInsets.only(bottom: 1),
        ),
        // 6 WEEKS x 7 DAYS
        Expanded(
          child: Column(
            children: List.generate(6, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(7, (col) {
                    final cellIndex = row * 7 + col;
                    DateTime cellDate;
                    bool isCurrentMonth = false;

                    if (cellIndex < leadingDays) {
                      final day = daysInPrevMonth - leadingDays + cellIndex + 1;
                      cellDate = DateTime(_displayedYear, _displayedMonth - 1, day);
                    } else if (cellIndex < leadingDays + daysInCurrentMonth) {
                      final day = cellIndex - leadingDays + 1;
                      cellDate = DateTime(_displayedYear, _displayedMonth, day);
                      isCurrentMonth = true;
                    } else {
                      final day = cellIndex - (leadingDays + daysInCurrentMonth) + 1;
                      cellDate = DateTime(_displayedYear, _displayedMonth + 1, day);
                    }

                    final isSelected = cellDate.year == _selectedDate.year &&
                        cellDate.month == _selectedDate.month &&
                        cellDate.day == _selectedDate.day;

                    final isToday = cellDate.year == now.year &&
                        cellDate.month == now.month &&
                        cellDate.day == now.day;

                    final isBeingSelected = _animatingSelectedDate != null &&
                        cellDate.year == _animatingSelectedDate!.year &&
                        cellDate.month == _animatingSelectedDate!.month &&
                        cellDate.day == _animatingSelectedDate!.day;

                    return Expanded(
                      child: InkWell(
                        onTap: () => _onDaySelected(cellDate),
                        hoverColor: isDark ? Colors.white12 : const Color(0xFFE5F1FB),
                        borderRadius: BorderRadius.circular(2),
                        child: AnimatedScale(
                          scale: isBeingSelected ? 0.89 : 1.0,
                          duration: const Duration(milliseconds: 80),
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.all(0.2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark ? Colors.blue.withValues(alpha: 0.35) : const Color(0xFFD6E8FF))
                                  : Colors.transparent,
                              border: isSelected
                                  ? Border.all(color: const Color(0xFF3399FF), width: 1.2)
                                  : (isToday
                                      ? Border.all(color: Colors.red.shade400, width: 0.8)
                                      : null),
                              borderRadius: BorderRadius.circular(isBeingSelected ? 3 : 2),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "${cellDate.day}",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
                                color: isCurrentMonth
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthGrid(bool isDark) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

    return Column(
      children: List.generate(4, (r) {
        return Expanded(
          child: Row(
            children: List.generate(3, (c) {
              final monthIdx = r * 3 + c + 1;
              final isSelected = monthIdx == _displayedMonth;
              final isBeingSelected = _animatingSelectedMonth == monthIdx;

              return Expanded(
                child: InkWell(
                  onTap: () => _onMonthSelected(monthIdx),
                  hoverColor: isDark ? Colors.white12 : const Color(0xFFE5F1FB),
                  borderRadius: BorderRadius.circular(2),
                  child: AnimatedScale(
                    scale: isBeingSelected ? 0.91 : 1.0,
                    duration: const Duration(milliseconds: 70),
                    curve: Curves.easeOutCubic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark ? Colors.blue.withValues(alpha: 0.35) : const Color(0xFFD6E8FF))
                            : Colors.transparent,
                        border: isSelected
                            ? Border.all(color: const Color(0xFF3399FF), width: 1.2)
                            : null,
                        borderRadius: BorderRadius.circular(isBeingSelected ? 3 : 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        months[monthIdx - 1],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final String label;
  const _WeekdayHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }
}

/// Fallback dialog kept for legacy compatibility if instantiated directly.
class AppDatePickerDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: DesktopCalendarDropdown(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        currentDate: currentDate,
        onDateSelected: (date) => Navigator.of(context).pop(date),
      ),
    );
  }
}
