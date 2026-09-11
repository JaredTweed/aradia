import 'package:aradia/resources/services/my_audio_handler.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';

class ProgressBarWidget extends StatelessWidget {
  final MyAudioHandler audioHandler;
  const ProgressBarWidget({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: audioHandler.getPositionStream(),
      builder: (context, snapshot) {
        final positionData = snapshot.data;
        final totalDuration = positionData?.duration ?? Duration.zero;
        final position = Duration(
            milliseconds: (positionData?.position.inMilliseconds ?? 0)
                .clamp(0, totalDuration.inMilliseconds));
        final buffered = Duration(
            milliseconds: (positionData?.bufferedPosition.inMilliseconds ?? 0)
                .clamp(0, totalDuration.inMilliseconds));
        final remainingTime = totalDuration - position;
        final colors = Theme.of(context).colorScheme;
        return Column(
          children: [
            ProgressBar(
              progressBarColor: colors.primary,
              thumbColor: colors.primary,
              baseBarColor: colors.surfaceContainerHighest,
              bufferedBarColor: colors.primary.withValues(alpha: 0.3),
              progress: position,
              buffered: buffered,
              total: totalDuration,
              onSeek: (duration) {
                audioHandler.seek(duration);
              },
            ),
            Text(
              "Time Remaining: ${remainingTime.inMinutes}:${(remainingTime.inSeconds % 60).toString().padLeft(2, '0')}",
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}
