import 'package:flutter/material.dart';
import '../../models/stock_geo_data.dart';

class StateDistrict3DViewer extends StatelessWidget {
  final String stateName;
  final dynamic stock;
  final GeoMetricType metric;
  final TimePeriod period;
  final Map<String, double> districtPercentages;
  final VoidCallback onBack;

  const StateDistrict3DViewer({
    super.key,
    required this.stateName,
    this.stock,
    required this.metric,
    required this.period,
    required this.districtPercentages,
    required this.onBack,
  });

  Color _getBarColor(double value) {
    if (value >= 25.0) return Colors.indigo.shade600;
    if (value >= 15.0) return Colors.teal.shade600;
    if (value >= 8.0) return Colors.amber.shade700;
    return Colors.deepOrange.shade500;
  }

  @override
  Widget build(BuildContext context) {
    final sortedDistricts = districtPercentages.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        // Header Bar
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).primaryColor.withOpacity(0.05),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
                tooltip: 'Back to India View',
              ),
              const SizedBox(width: 8),
              Text(
                'District View: $stateName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Chip(
                label: Text(
                  'Metric: ${metric.name}',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.blue.shade50,
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  'Period: ${period.name}',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.green.shade50,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // District Grid/List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedDistricts.length,
            itemBuilder: (context, index) {
              final entry = sortedDistricts[index];
              final districtName = entry.key;
              final percentage = entry.value;
              final color = _getBarColor(percentage);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            districtName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (percentage / 100.0).clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
