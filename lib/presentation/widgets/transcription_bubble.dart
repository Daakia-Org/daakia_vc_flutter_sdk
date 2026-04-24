import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_viewmodel.dart';
import 'package:flutter/material.dart';

import '../../model/transcription_model.dart';

class TranscriptionBubble extends StatelessWidget {
  final TranscriptionModel transcriptionData;
  final RtcViewmodel viewModel;
  final bool showTranslation;

  const TranscriptionBubble({
    required this.transcriptionData,
    required this.viewModel,
    this.showTranslation = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasTranslation = showTranslation &&
        transcriptionData.translatedTranscription != null &&
        transcriptionData.translatedTranscription!.isNotEmpty;

    final initial = transcriptionData.name.isNotEmpty
        ? transcriptionData.name[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.blueGrey.shade700,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        transcriptionData.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      transcriptionData.timestamp,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C2E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transcriptionData.transcription,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      if (hasTranslation) ...[
                        const SizedBox(height: 8),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 3,
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  transcriptionData.translatedTranscription!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
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