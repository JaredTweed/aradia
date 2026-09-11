import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

void openBookDetails(BuildContext context, Audiobook book,
    [List<AudiobookFile>? files]) {
  context.read<WeSlideController>().hide();
  context.push('/audiobook-details', extra: {
    'audiobook': book,
    'isDownload': book.origin == 'download',
    'isLocal': book.origin == 'local',
    if (book.origin == 'local') 'files': files,
  });
}
