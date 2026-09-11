import 'package:aradia/widgets/local_book_editor.dart';
import 'package:aradia/resources/services/local/local_book_library.dart';
import 'package:aradia/utils/book_navigation.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/services/local/cover_image_service.dart';

class LocalAudiobookItem extends StatelessWidget {
  final LocalAudiobook audiobook;
  final double width;
  final double height;
  final VoidCallback? onUpdated;

  const LocalAudiobookItem({
    super.key,
    required this.audiobook,
    this.width = 175.0,
    this.height = 250.0,
    this.onUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Ink(
      width: width,
      height: height,
      child: Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          splashColor: AppColors.primaryColor,
          splashFactory: InkRipple.splashFactory,
          onLongPress: () => _showEditDialog(context),
          onTap: () => _openDetails(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                child: _buildCoverImage(),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: width,
                      child: Text(
                        audiobook.title,
                        style: GoogleFonts.ubuntu(
                          textStyle: const TextStyle(
                            overflow: TextOverflow.ellipsis,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      audiobook.author,
                      style: GoogleFonts.ubuntu(
                        textStyle: const TextStyle(
                          overflow: TextOverflow.ellipsis,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.audiotrack,
                                size: 14, color: AppColors.primaryColor),
                            const SizedBox(width: 4),
                            Text(
                              '${audiobook.audioFiles.length} files',
                              style: GoogleFonts.ubuntu(
                                textStyle: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (audiobook.totalDuration != null)
                          Text(
                            audiobook.formattedDuration,
                            style: GoogleFonts.ubuntu(
                              textStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    return FutureBuilder<String?>(
      future: resolveCoverForLocal(audiobook),
      builder: (context, snapshot) {
        final v = snapshot.data;
        if (v != null && v.isNotEmpty) {
          return Image(
            image: coverProvider(v),
            width: width,
            height: width,
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) => _buildPlaceholderCover(),
          );
        }
        return _buildPlaceholderCover();
      },
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryColor.withValues(alpha: 0.7),
            AppColors.primaryColor,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.headphones,
              size: 48, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              audiobook.title,
              style: GoogleFonts.ubuntu(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => LocalBookEditor(
        audiobook: audiobook,
        onUpdated: onUpdated,
      ),
    );
  }

  Future<void> _openDetails(BuildContext context) async {
    try {
      final book = await LocalBookLibrary.audiobook(audiobook);
      if (context.mounted) openBookDetails(context, book);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not open this book: $error")));
      }
    }
  }
}
