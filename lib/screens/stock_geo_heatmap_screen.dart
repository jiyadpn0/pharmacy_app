import 'package:flutter/material.dart';
import '../models/stock_geo_data.dart';
import '../services/geo_data_service.dart';
import '../widgets/geo_map/state_district_3d_viewer.dart';

typedef MapCallback = void Function(String id, String name, TapDownDetails? tapDetails);

class SimpleMap extends StatelessWidget {
  final MapCallback callback;
  final Map<String, double> percentageMap;

  const SimpleMap({
    super.key,
    required this.callback,
    required this.percentageMap,
  });

  static const List<Map<String, String>> states = [
    {'id': 'KL', 'name': 'Kerala'},
    {'id': 'MH', 'name': 'Maharashtra'},
    {'id': 'GJ', 'name': 'Gujarat'},
    {'id': 'TN', 'name': 'Tamil Nadu'},
    {'id': 'KA', 'name': 'Karnataka'},
    {'id': 'UP', 'name': 'Uttar Pradesh'},
    {'id': 'RJ', 'name': 'Rajasthan'},
    {'id': 'WB', 'name': 'West Bengal'},
    {'id': 'TS', 'name': 'Telangana'},
    {'id': 'AP', 'name': 'Andhra Pradesh'},
    {'id': 'MP', 'name': 'Madhya Pradesh'},
    {'id': 'PB', 'name': 'Punjab'},
    {'id': 'HR', 'name': 'Haryana'},
    {'id': 'BR', 'name': 'Bihar'},
    {'id': 'OR', 'name': 'Odisha'},
    {'id': 'AS', 'name': 'Assam'},
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: states.length,
      itemBuilder: (context, index) {
        final stateInfo = states[index];
        final id = stateInfo['id']!;
        final name = stateInfo['name']!;
        final value = percentageMap[name] ?? 0.0;

        return InkWell(
          onTapDown: (tapDetails) {
            callback(id, name, tapDetails);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${value.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class StockGeoHeatmapScreen extends StatefulWidget {
  const StockGeoHeatmapScreen({super.key});

  @override
  State<StockGeoHeatmapScreen> createState() => _StockGeoHeatmapScreenState();
}

class _StockGeoHeatmapScreenState extends State<StockGeoHeatmapScreen> {
  final GeoDataService _geoData = GeoDataService();
  String? _activeStateForDistricts;
  String? _selectedRegionName;
  double? _selectedRegionValue;
  GeoMetricType _selectedMetric = GeoMetricType.stockValue;
  TimePeriod _selectedTimePeriod = TimePeriod.thisMonth;
  dynamic _currentStock;

  final Map<String, double> percentageMap = {
    'Kerala': 18.5,
    'Maharashtra': 22.0,
    'Gujarat': 14.2,
    'Tamil Nadu': 12.8,
    'Karnataka': 11.5,
    'Uttar Pradesh': 8.4,
    'Rajasthan': 4.1,
    'West Bengal': 3.5,
    'Telangana': 2.5,
    'Andhra Pradesh': 2.5,
  };

  String _resolveRegionName(String id, String name, bool isIndia) {
    if (name.isNotEmpty) return name;
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Geo Heatmap'),
        actions: [
          DropdownButton<GeoMetricType>(
            value: _selectedMetric,
            underline: const SizedBox(),
            onChanged: (metric) {
              if (metric != null) {
                setState(() => _selectedMetric = metric);
              }
            },
            items: GeoMetricType.values.map((m) {
              return DropdownMenuItem(
                value: m,
                child: Text(m.name),
              );
            }).toList(),
          ),
          const SizedBox(width: 16),
          DropdownButton<TimePeriod>(
            value: _selectedTimePeriod,
            underline: const SizedBox(),
            onChanged: (period) {
              if (period != null) {
                setState(() => _selectedTimePeriod = period);
              }
            },
            items: TimePeriod.values.map((p) {
              return DropdownMenuItem(
                value: p,
                child: Text(p.name),
              );
            }).toList(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          if (_selectedRegionName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  Text(
                    'Selected Region: $_selectedRegionName (${_selectedRegionValue?.toStringAsFixed(1) ?? '0.0'}%)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _selectedRegionName = null;
                        _selectedRegionValue = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: _activeStateForDistricts != null
                ? StateDistrict3DViewer(
                    stateName: _activeStateForDistricts!,
                    stock: _currentStock,
                    metric: _selectedMetric,
                    period: _selectedTimePeriod,
                    districtPercentages: _geoData.getDistrictPercentageMap(
                      stateName: _activeStateForDistricts!,
                      metric: _selectedMetric,
                      period: _selectedTimePeriod,
                    ),
                    onBack: () => setState(() => _activeStateForDistricts = null),
                  )
                : Stack(
                    children: [
                      InteractiveViewer(
                        boundaryMargin: const EdgeInsets.all(20),
                        minScale: 0.5,
                        maxScale: 3.0,
                        child: SimpleMap(
                          percentageMap: percentageMap,
                          callback: (id, name, tapDetails) {
                            final resolved = _resolveRegionName(id, name, true);
                            setState(() {
                              _selectedRegionName = resolved;
                              _selectedRegionValue = percentageMap[resolved];
                              _activeStateForDistricts = resolved; // Opens the 2D district view for this state
                            });
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
