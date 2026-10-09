import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../rtc/audio_routing.dart';

bool isExternalAudioDevice(String label) {
  final l = label.toLowerCase();
  return !l.contains('earpiece') &&
      !l.contains('receiver') && // iOS earpiece label
      !l.contains('speakerphone') &&
      !l.contains('speaker');
}

// iOS port types (MediaDevice.groupId) of headset microphones that stay in
// availableInputs while overrideOutputAudioPort(.speaker) hides the headset's
// output from the current route: Bluetooth HFP/LE, 3.5mm/Lightning headset mic
// ("MicrophoneWired") and USB-C headsets ("USBAudio").
bool isExternalInputPort(String? groupId) {
  final g = (groupId ?? '').toLowerCase();
  return g.contains('bluetooth') ||
      g.contains('microphonewired') ||
      g.contains('usbaudio');
}

// Wired/USB headset port types, used to pick the headset icon when the device
// name ("EarPods") doesn't say "headphone" or "headset".
bool isWiredHeadsetPort(String? groupId) {
  final g = (groupId ?? '').toLowerCase();
  return g.contains('headphones') ||
      g.contains('microphonewired') ||
      g.contains('usbaudio') ||
      g.contains('headsetmic');
}

// On iOS, enumerateDevices only returns currentRoute.outputs for audiooutput.
// When overrideOutputAudioPort(.speaker) is active the route shows only Speaker,
// hiding any connected BT device. BT HFP still appears in availableInputs (audioinput),
// so we detect it there and inject the corresponding output entry.
// We also always inject virtual Speaker + Earpiece entries.
List<MediaDevice> augmentOutputsForIos(List<MediaDevice> allDevices) {
  final audioOutputs = allDevices.where((d) => d.kind == 'audiooutput').toList();
  if (defaultTargetPlatform != TargetPlatform.iOS) return audioOutputs;

  bool isBluetooth(MediaDevice d) =>
      (d.groupId ?? '').toLowerCase().contains('bluetooth');
  bool isEarpiece(MediaDevice d) {
    final l = d.label.toLowerCase();
    return l.contains('receiver') || l.contains('earpiece');
  }

  // iOS names the earpiece "Receiver" when it's the current route; show the
  // same "Earpiece" label the virtual entry below uses.
  final result = audioOutputs
      .map((d) => isEarpiece(d)
          ? MediaDevice(d.deviceId, 'Earpiece', d.kind, d.groupId)
          : d)
      .toList();

  // Promote headsets found in audioinput (availableInputs) to the output list.
  // Their mic stays in availableInputs even when speaker is forced and the
  // headset's output is missing from the current route.
  for (final input in allDevices.where((d) => d.kind == 'audioinput')) {
    if (!isExternalInputPort(input.groupId)) continue;
    if (result.any((o) => o.deviceId == input.deviceId)) continue;
    final isWired = !isBluetooth(input);
    // The same buds show up as an A2DP output and an HFP input with different
    // ids; one Bluetooth row is enough.
    if (!isWired && result.any(isBluetooth)) continue;
    // A wired headset's output is already listed when it's the current route.
    if (isWired && result.any((o) => isWiredHeadsetPort(o.groupId))) continue;
    // "EarPods Microphone" -> "EarPods".
    final label = isWired
        ? input.label.replaceFirst(RegExp(r'\s*microphone$', caseSensitive: false), '')
        : input.label;
    result.add(MediaDevice(input.deviceId, label.isEmpty ? input.label : label,
        'audiooutput', input.groupId));
  }

  final hasExternal = result.any((d) => isExternalAudioDevice(d.label));

  // Ensure Speaker is always present and at the top.
  if (!result.any((d) => d.label.toLowerCase().contains('speaker'))) {
    result.insert(0, const MediaDevice('Speaker', 'Speaker', 'audiooutput', 'Speaker'));
  } else {
    final idx = result.indexWhere((d) => d.label.toLowerCase().contains('speaker'));
    if (idx > 0) result.insert(0, result.removeAt(idx));
  }

  // Show Earpiece only when no BT/wired is connected (iOS can't force earpiece
  // over BT). iOS can briefly report the earpiece as the current route while a
  // headset connects, so drop that entry too rather than listing both.
  if (hasExternal) {
    result.removeWhere(isEarpiece);
  } else if (!result.any(isEarpiece)) {
    result.add(const MediaDevice('Earpiece', 'Earpiece', 'audiooutput', 'Receiver'));
  }

  return result;
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
    _subscription = DaakiaAudioRouting.onDeviceChange.listen(_onDeviceChange);
  }

  void _onDeviceChange(List<MediaDevice> devices) {
    final augmented = augmentOutputsForIos(devices);
    if (mounted) setState(() => _devices = augmented);
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
        : l.contains('earpiece') || l.contains('receiver');
  }

  // groupId on iOS is AVAudioSession portType (e.g. "BluetoothHFP", "BluetoothA2DP").
  IconData _iconForDevice(MediaDevice device) {
    final l = device.label.toLowerCase();
    final g = (device.groupId ?? '').toLowerCase();
    if (g.contains('bluetooth') ||
        l.contains('bluetooth') ||
        l.contains('airpods') ||
        l.contains('wireless')) {
      return Icons.bluetooth_audio;
    }
    if (l.contains('headphone') ||
        l.contains('headset') ||
        isWiredHeadsetPort(device.groupId)) {
      return Icons.headset;
    }
    if (l.contains('speakerphone') || l.contains('speaker')) {
      return Icons.volume_up;
    }
    if (l.contains('earpiece') || l.contains('receiver')) return Icons.hearing;
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
                  icon: _iconForDevice(device),
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
