import 'dart:io';
import 'package:aradia/resources/services/local/cover_image_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class LowAndHighImage extends StatelessWidget {
  final String lowQImage;
  final String? highQImage;
  final double height;
  final double width;

  const LowAndHighImage({
    super.key,
    required this.lowQImage,
    required this.highQImage,
    this.height = 200,
    this.width = 200,
  });

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.headphones)),
        );

    Widget image(String path, Widget Function() fallback) {
      if (path.isEmpty) return fallback();
      final local = asLocalPath(path);
      if (local != null) {
        return Image.file(File(local),
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback());
      }
      return CachedNetworkImage(
        imageUrl: path,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder(),
        errorWidget: (_, __, ___) => fallback(),
      );
    }

    final main = highQImage?.isNotEmpty == true ? highQImage! : lowQImage;
    return SizedBox(
      height: height,
      width: width,
      child: image(
          main,
          () => main == lowQImage
              ? placeholder()
              : image(lowQImage, placeholder)),
    );
  }
}
