import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/helios_colors.dart';

/// Expandable search bar with Nominatim geocoding for any map view.
///
/// Accepts a [MapController] to fly to selected results and an optional
/// [onLocationSelected] callback for additional handling.
class MapSearchBar extends StatefulWidget {
  const MapSearchBar({
    super.key,
    required this.mapController,
    this.onLocationSelected,
  });

  final MapController mapController;
  final void Function(LatLng location)? onLocationSelected;

  @override
  State<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<MapSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}&format=json&limit=5',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'HeliosGCS/1.0');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final List<dynamic> data = jsonDecode(body) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _results = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectResult(Map<String, dynamic> result) {
    final lat = double.tryParse(result['lat']?.toString() ?? '');
    final lon = double.tryParse(result['lon']?.toString() ?? '');
    if (lat != null && lon != null) {
      final location = LatLng(lat, lon);
      widget.mapController.move(location, 15);
      widget.onLocationSelected?.call(location);
    }
    setState(() {
      _results = [];
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  void _clearSearch() {
    setState(() {
      _results = [];
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 280,
          height: 40,
          decoration: BoxDecoration(
            color: hc.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.search, size: 18, color: hc.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      _clearSearch();
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onChanged,
                    style: TextStyle(
                      fontSize: 13,
                      color: hc.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search location\u2026',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: hc.textTertiary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: hc.accent,
                    ),
                  ),
                )
              else if (_controller.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: hc.textTertiary),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _clearSearch,
                )
              else
                const SizedBox(width: 10),
            ],
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            width: 280,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: hc.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hc.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _results.map((r) {
                final displayName =
                    r['display_name']?.toString() ?? 'Unknown';
                return InkWell(
                  onTap: () => _selectResult(r),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: hc.textPrimary),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
