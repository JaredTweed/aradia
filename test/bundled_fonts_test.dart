import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every UI font variant loads from bundled assets without network access',
      () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      GoogleFonts.ubuntu(fontWeight: weight);
    }
    GoogleFonts.lato();
    GoogleFonts.lato(fontWeight: FontWeight.w600);
    await GoogleFonts.pendingFonts();
  });
}
