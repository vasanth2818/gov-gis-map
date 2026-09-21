import 'package:flutter/material.dart';

class GnssStatusWidget extends StatelessWidget {
  final Function(String) onProviderSwitch;
  final String currentProvider;
  final String providerStatus;
  final double accuracy;
  final int satelliteCount;
  final String fixType;

  final VoidCallback? onAddProvider;

  const GnssStatusWidget({
    Key? key,
    required this.onProviderSwitch,
    required this.currentProvider,
    required this.providerStatus,
    required this.accuracy,
    required this.satelliteCount,
    required this.fixType,
    this.onAddProvider,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );
    const valueStyle = TextStyle(
      color: Colors.black87,
      fontWeight: FontWeight.bold,
      fontSize: 13,
    );

    return Card(
      elevation: 6,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white, width: 2),
      ),
      color: Colors.white.withOpacity(0.95),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gps_fixed, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'GNSS / LOCATION STATUS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(height: 1, thickness: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Source:', style: labelStyle),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currentProvider,
                    isDense: true,
                    dropdownColor: Colors.white,
                    style: valueStyle.copyWith(color: Colors.blue.shade700),
                    items: const [
                      DropdownMenuItem(
                        value: 'Device GPS',
                        child: Text('Device GPS'),
                      ),
                      DropdownMenuItem(
                        value: 'Mock GNSS',
                        child: Text('Mock GNSS'),
                      ),
                      DropdownMenuItem(
                        value: 'Real GNSS',
                          child: Text('Real GNSS'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onProviderSwitch(value);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (currentProvider == 'Real GNSS' && onAddProvider != null) ...[
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onAddProvider,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.bluetooth, size: 18),
                      SizedBox(width: 8),
                      Text('|'),
                      SizedBox(width: 8),
                      Icon(Icons.usb, size: 18),
                      SizedBox(width: 8),

                      Text('Add GNSS Provider'),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            _buildDataRow('Status', providerStatus, labelStyle, valueStyle),
            _buildDataRow('Accuracy', '${accuracy.toStringAsFixed(2)} m', labelStyle, valueStyle),
            _buildDataRow('Satellites', satelliteCount.toString(), labelStyle, valueStyle),
            _buildDataRow('Fix Type', fixType, labelStyle, valueStyle),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value, TextStyle labelStyle, TextStyle valueStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: labelStyle),
          Flexible(
            child: Text(
              value,
              style: valueStyle,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
