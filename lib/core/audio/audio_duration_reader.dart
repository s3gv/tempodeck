import 'dart:io';
import 'dart:typed_data';

/// Reads the duration of an audio file from its header without loading it
/// into the audio engine. Supports WAV, MP3, OGG Vorbis, and FLAC formats.
///
/// This is used on desktop to avoid calling SoLoud.loadFile() for duration
/// probing, which would interfere with the preview player's source cache.
class AudioDurationReader {
  const AudioDurationReader();

  /// Returns the duration of the audio file, or `null` if it cannot be
  /// determined from the header.
  Future<Duration?> readDuration(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.wav')) {
      return _readWavDuration(file);
    } else if (lowerPath.endsWith('.mp3')) {
      return _readMp3Duration(file);
    } else if (lowerPath.endsWith('.ogg')) {
      return _readOggVorbisDuration(file);
    } else if (lowerPath.endsWith('.flac')) {
      return _readFlacDuration(file);
    }
    // Unsupported format — caller should fall back to a default.
    return null;
  }

  /// Parse WAV RIFF header to compute duration.
  /// Duration = dataChunkSize / (sampleRate * channelCount * bitsPerSample/8)
  Future<Duration?> _readWavDuration(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final header = await raf.read(44);
        if (header.length < 44) return null;

        final riff = String.fromCharCodes(header.sublist(0, 4));
        final wave = String.fromCharCodes(header.sublist(8, 12));
        if (riff != 'RIFF' || wave != 'WAVE') return null;

        final byteData = ByteData.sublistView(header);
        final channelCount = byteData.getUint16(22, Endian.little);
        final sampleRate = byteData.getUint32(24, Endian.little);
        final bitsPerSample = byteData.getUint16(34, Endian.little);

        if (sampleRate == 0 || channelCount == 0 || bitsPerSample == 0) {
          return null;
        }

        // Find the 'data' chunk to get the actual data size.
        // The data chunk may not start at offset 36 if there are extra chunks.
        var offset = 12; // skip RIFF header
        await raf.setPosition(offset);

        while (offset < await file.length() - 8) {
          final chunkHeader = await raf.read(8);
          if (chunkHeader.length < 8) break;

          final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
          final chunkSize = ByteData.sublistView(chunkHeader)
              .getUint32(4, Endian.little);

          if (chunkId == 'data') {
            final bytesPerSecond =
                sampleRate * channelCount * (bitsPerSample ~/ 8);
            final durationMs = (chunkSize * 1000 / bytesPerSecond).round();
            return Duration(milliseconds: durationMs);
          }

          offset += 8 + chunkSize;
          // Chunks are word-aligned (2-byte boundary).
          if (chunkSize.isOdd) offset++;
          await raf.setPosition(offset);
        }

        return null;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Estimate MP3 duration from file size and first frame bitrate.
  /// This is approximate but good enough for waveform offset calculation.
  Future<Duration?> _readMp3Duration(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        // Skip ID3v2 tag if present.
        final id3Header = await raf.read(10);
        if (id3Header.length < 10) return null;

        var dataStart = 0;
        if (id3Header[0] == 0x49 &&
            id3Header[1] == 0x44 &&
            id3Header[2] == 0x33) {
          // ID3v2 tag size is stored as synchsafe integer in bytes 6-9.
          final tagSize = ((id3Header[6] & 0x7F) << 21) |
              ((id3Header[7] & 0x7F) << 14) |
              ((id3Header[8] & 0x7F) << 7) |
              (id3Header[9] & 0x7F);
          dataStart = 10 + tagSize;
        }

        // Find first sync word (0xFF 0xE0+).
        await raf.setPosition(dataStart);
        final searchBuffer = await raf.read(4096);
        int? frameOffset;

        for (var i = 0; i < searchBuffer.length - 1; i++) {
          if (searchBuffer[i] == 0xFF && (searchBuffer[i + 1] & 0xE0) == 0xE0) {
            frameOffset = i;
            break;
          }
        }

        if (frameOffset == null) return null;

        final frameHeader = searchBuffer.sublist(frameOffset, frameOffset + 4);
        final bitrate = _mp3Bitrate(frameHeader);
        if (bitrate == null || bitrate == 0) return null;

        final fileSize = await file.length();
        final audioSize = fileSize - dataStart;
        final durationMs = (audioSize * 8 / (bitrate * 1000) * 1000).round();
        return Duration(milliseconds: durationMs);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Decode bitrate from MP3 frame header (MPEG 1 Layer 3).
  int? _mp3Bitrate(List<int> header) {
    if (header.length < 4) return null;

    final version = (header[1] >> 3) & 0x03; // 00=2.5, 01=reserved, 10=2, 11=1
    final layer = (header[1] >> 1) & 0x03; // 01=III, 10=II, 11=I
    final bitrateIndex = (header[2] >> 4) & 0x0F;

    if (bitrateIndex == 0 || bitrateIndex == 15) return null;

    // MPEG 1, Layer III bitrate table (kbps).
    const mpeg1Layer3 = [
      0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
    ];

    // MPEG 2/2.5, Layer III bitrate table (kbps).
    const mpeg2Layer3 = [
      0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
    ];

    if (version == 0x03 && layer == 0x01) {
      // MPEG 1, Layer III
      return mpeg1Layer3[bitrateIndex];
    } else if ((version == 0x02 || version == 0x00) && layer == 0x01) {
      // MPEG 2 or 2.5, Layer III
      return mpeg2Layer3[bitrateIndex];
    }

    // Fallback for other layer combinations — use MPEG1 L3 table.
    return mpeg1Layer3[bitrateIndex];
  }

  /// Parse OGG Vorbis to extract duration.
  ///
  /// OGG files contain a Vorbis identification header with the sample rate.
  /// We estimate duration from file size and a typical bitrate, since reading
  /// the exact granule position of the last page is complex.
  /// Falls back to bitrate estimation: fileSize * 8 / averageBitrate.
  Future<Duration?> _readOggVorbisDuration(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        // Read enough to find the Vorbis identification header.
        final header = await raf.read(58);
        if (header.length < 58) return null;

        // Verify OGG page header: "OggS"
        final oggs = String.fromCharCodes(header.sublist(0, 4));
        if (oggs != 'OggS') return null;

        // The Vorbis identification header starts after the OGG page header.
        // Page header is typically 27 + segment_count bytes.
        final segmentCount = header[26];
        final headerSize = 27 + segmentCount;

        await raf.setPosition(headerSize);
        final vorbisHeader = await raf.read(30);
        if (vorbisHeader.length < 16) return null;

        // Check for Vorbis identification header: 0x01 + "vorbis"
        if (vorbisHeader[0] != 0x01 ||
            String.fromCharCodes(vorbisHeader.sublist(1, 7)) != 'vorbis') {
          return null;
        }

        // Sample rate is at offset 12 in the Vorbis identification header.
        final byteData = ByteData.sublistView(Uint8List.fromList(vorbisHeader));
        final sampleRate = byteData.getUint32(12, Endian.little);
        if (sampleRate == 0) return null;

        // Read the last OGG page to get the granule position (= total samples).
        final fileSize = await file.length();
        final tailSize = fileSize < 65536 ? fileSize : 65536;
        await raf.setPosition(fileSize - tailSize);
        final tail = await raf.read(tailSize);

        // Search backwards for the last "OggS" sync pattern.
        int? lastPageOffset;
        for (var i = tail.length - 4; i >= 0; i--) {
          if (tail[i] == 0x4F &&
              tail[i + 1] == 0x67 &&
              tail[i + 2] == 0x67 &&
              tail[i + 3] == 0x53) {
            lastPageOffset = i;
            break;
          }
        }

        if (lastPageOffset != null && lastPageOffset + 14 <= tail.length) {
          // Granule position is at offset 6 in the OGG page header (8 bytes).
          final pageData =
              ByteData.sublistView(Uint8List.fromList(tail), lastPageOffset);
          final granulePosition = pageData.getInt64(6, Endian.little);
          if (granulePosition > 0) {
            final durationMs =
                (granulePosition * 1000 / sampleRate).round();
            return Duration(milliseconds: durationMs);
          }
        }

        // Fallback: estimate from file size assuming ~128kbps average.
        const kFallbackBitrateKbps = 128;
        final durationMs =
            (fileSize * 8 / (kFallbackBitrateKbps * 1000) * 1000).round();
        return Duration(milliseconds: durationMs);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Parse FLAC STREAMINFO metadata block to compute exact duration.
  ///
  /// FLAC files start with "fLaC" followed by metadata blocks. The first
  /// (mandatory) block is STREAMINFO which contains the sample rate and
  /// total number of samples.
  Future<Duration?> _readFlacDuration(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final header = await raf.read(42);
        if (header.length < 42) return null;

        // Verify FLAC stream marker: "fLaC"
        final marker = String.fromCharCodes(header.sublist(0, 4));
        if (marker != 'fLaC') return null;

        // Metadata block header at offset 4:
        //   byte 0: bit 7 = last-block flag, bits 6-0 = block type (0=STREAMINFO)
        //   bytes 1-3: block length
        final blockType = header[4] & 0x7F;
        if (blockType != 0) return null; // First block must be STREAMINFO.

        // STREAMINFO block starts at offset 8 and is 34 bytes.
        // Bytes 10-12 (within STREAMINFO): sample rate (20 bits) at bit offset 80.
        // Actually layout from FLAC spec (offset within STREAMINFO):
        //   bytes 0-1: min block size
        //   bytes 2-3: max block size
        //   bytes 4-6: min frame size
        //   bytes 7-9: max frame size
        //   bytes 10-13: sample rate (20 bits) | channels (3 bits) |
        //                bits-per-sample (5 bits) | total samples (36 bits)
        //   bytes 14-17: total samples (continued)

        final streamInfo = header.sublist(8, 42);
        final byteData = ByteData.sublistView(Uint8List.fromList(streamInfo));

        // Sample rate: bits 0-19 of bytes 10-12 (big-endian).
        final sampleRateHigh = byteData.getUint16(10, Endian.big);
        final sampleRateLow = (streamInfo[12] >> 4) & 0x0F;
        final sampleRate = (sampleRateHigh << 4) | sampleRateLow;
        if (sampleRate == 0) return null;

        // Total samples: 36 bits starting at bit 4 of byte 13.
        // byte 13 bits 3-0 = top 4 bits of total samples
        // bytes 14-17 = lower 32 bits
        final totalSamplesHigh = streamInfo[13] & 0x0F;
        final totalSamplesLow = byteData.getUint32(14, Endian.big);
        final totalSamples =
            (totalSamplesHigh << 32) | totalSamplesLow;

        if (totalSamples == 0) return null;

        final durationMs = (totalSamples * 1000 / sampleRate).round();
        return Duration(milliseconds: durationMs);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }
}
