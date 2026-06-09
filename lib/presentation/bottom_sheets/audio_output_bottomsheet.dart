import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

bool isExternalAudioDevice(String label) {
  final l = label.toLowerCase();
  return !l.contains('earpiece') &&
      !l.contains('speakerphone') &&
      !l.contains('speaker');
}

class AudioOutputSheet extends StatefulWidget {
  final bool speakerphoneOn;
  final List<MediaDevice> initialDevices;
  final MediaDevice? selectedDevice;
  final void Function(MediaDevice) onDeviceSelected;

  const AudioOutputSheet({
    super.key,
    required this.speakerphoneOn,
    required this.initialDevices,
    required this.selectedDevice,
    required this.onDeviceSelected,
  });

  @override
  State<AudioOutputSheet> createState() => _AudioOutputSheetState();
}

class _AudioOutputSheetState extends State<AudioOutputSheet> {
  late List<MediaDevice> _devices;
  StreamSubscription<List<MediaDevice>>? _subscription;

  @override
  void initState() {
    super.initState();
    _devices = widget.initialDevices;
    _subscription =
        Hardware.instance.onDeviceChange.stream.listen(_onDeviceChange);
  }

  void _onDeviceChange(List<MediaDevice> devices) {
    final outputs = devices.where((d) => d.kind == 'audiooutput').toList();
    if (mounted) setState(() => _devices = outputs);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  bool _isSelected(MediaDevice device) {
    if (widget.selectedDevice != null) {
      return widget.selectedDevice!.deviceId == device.deviceId;
    }
    final l = device.label.toLowerCase();
    final isSpeaker = l.contains('speakerphone') || l.contains('speaker');
    if (isSpeaker) return widget.speakerphoneOn;
    if (widget.speakerphoneOn) return false;
    // speakerphoneOn=false: OS routes to the best external device first
    // (BT/wired headset), falling back to earpiece when none is connected.
    final hasExternal = _devices.any((d) => isExternalAudioDevice(d.label));
    return hasExternal
        ? isExternalAudioDevice(device.label)
        : l.contains('earpiece');
  }

  IconData _iconForDevice(String label) {
    final l = label.toLowerCase();
    if (l.contains('bluetooth') ||
        l.contains('airpods') ||
        l.contains('wireless')) {
      return Icons.bluetooth_audio;
    }
    if (l.contains('headphone') || l.contains('headset')) return Icons.headset;
    if (l.contains('speakerphone') || l.contains('speaker')) {
      return Icons.volume_up;
    }
    if (l.contains('earpiece')) return Icons.hearing;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Audio Output',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'No audio devices found',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ..._devices.map(
                (device) => _AudioDeviceOption(
                  icon: _iconForDevice(device.label),
                  label: device.label,
                  isSelected: _isSelected(device),
                  onTap: () => widget.onDeviceSelected(device),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AudioDeviceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AudioDeviceOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.blue : Colors.white;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
      onTap: onTap,
    );
  }
}
