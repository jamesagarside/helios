import 'package:flutter/material.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';

/// Analyse View — DuckDB analytics screen.
///
/// Flight browser, SQL editor, results table, and template gallery.
class AnalyseView extends StatelessWidget {
  const AnalyseView({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showBrowser = width >= 768;

    return Row(
      children: [
        // Flight browser panel (desktop/tablet)
        if (showBrowser)
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: HeliosColors.surface,
                  child: Row(
                    children: [
                      Text('Flights', style: HeliosTypography.heading2),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () {},
                        tooltip: 'Refresh',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: HeliosColors.border),
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No recorded flights yet.\nConnect to a vehicle and start recording.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (showBrowser)
          const VerticalDivider(width: 1, color: HeliosColors.border),
        // Main area — SQL editor + results
        Expanded(
          child: Column(
            children: [
              // Template buttons
              Container(
                height: 44,
                color: HeliosColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _TemplateChip(label: 'Vibration', icon: Icons.vibration),
                    _TemplateChip(label: 'Battery', icon: Icons.battery_full),
                    _TemplateChip(label: 'GPS', icon: Icons.gps_fixed),
                    _TemplateChip(label: 'Altitude', icon: Icons.height),
                    _TemplateChip(label: 'Anomaly', icon: Icons.warning_amber),
                    _TemplateChip(label: 'Summary', icon: Icons.summarize),
                    _TemplateChip(label: 'Modes', icon: Icons.timeline),
                  ],
                ),
              ),
              const Divider(height: 1, color: HeliosColors.border),
              // SQL editor
              Container(
                height: 120,
                color: HeliosColors.surfaceDim,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: TextField(
                        maxLines: null,
                        style: HeliosTypography.sqlEditor,
                        decoration: const InputDecoration(
                          hintText: 'SELECT * FROM attitude LIMIT 100',
                          border: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Run'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.show_chart, size: 16),
                          label: const Text('Chart'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.save_alt, size: 16),
                          label: const Text('Export'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: HeliosColors.border),
              // Results area
              const Expanded(
                child: Center(
                  child: Text(
                    'Run a query to see results',
                    style: TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
      child: ActionChip(
        avatar: Icon(icon, size: 14, color: HeliosColors.accent),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        backgroundColor: HeliosColors.surfaceLight,
        side: const BorderSide(color: HeliosColors.border),
        onPressed: () {},
      ),
    );
  }
}
