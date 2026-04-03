import 'package:flutter/material.dart';
import '../theme/helios_colors.dart';

/// Definition for a single tool button in an expandable column.
class ToolButtonDef {
  const ToolButtonDef({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final bool active;
}

/// A column of icon buttons that expand to show labels when the user
/// hovers over any button in the group.
///
/// On hover: all buttons animate to show icon + label text.
/// On exit: all buttons collapse back to icon-only.
class ExpandableToolColumn extends StatefulWidget {
  const ExpandableToolColumn({
    super.key,
    required this.buttons,
    this.spacing = 4,
  });

  final List<ToolButtonDef> buttons;
  final double spacing;

  @override
  State<ExpandableToolColumn> createState() => _ExpandableToolColumnState();
}

class _ExpandableToolColumnState extends State<ExpandableToolColumn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < widget.buttons.length; i++) ...[
            if (i > 0) SizedBox(height: widget.spacing),
            _ExpandableButton(
              def: widget.buttons[i],
              expanded: _hovered,
              hc: hc,
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandableButton extends StatelessWidget {
  const _ExpandableButton({
    required this.def,
    required this.expanded,
    required this.hc,
  });

  final ToolButtonDef def;
  final bool expanded;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    final iconColor = def.color ?? (def.active ? hc.accent : hc.textSecondary);
    final bgColor = def.active
        ? hc.accent.withValues(alpha: 0.15)
        : hc.surface.withValues(alpha: 0.85);

    return GestureDetector(
      onTap: def.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: expanded ? 10 : 8,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: def.active
                ? hc.accent.withValues(alpha: 0.5)
                : hc.border.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(def.icon, size: 18, color: iconColor),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        def.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: iconColor,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
