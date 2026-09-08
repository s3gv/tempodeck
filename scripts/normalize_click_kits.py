#!/usr/bin/env python3
"""Normalize click kit WAV assets to -1 dBFS peak per kit.

For each kit directory, finds the global peak across all 4 variants and applies
a uniform gain so the loudest sample reaches -1 dBFS. This preserves the
relative volume hierarchy within each kit (accent_high > normal > subdivision).

Reads PCM 16-bit, PCM 24-bit, PCM 32-bit, and IEEE float 32-bit WAV formats.
Write-back is supported for PCM 16-bit, PCM 32-bit, and IEEE float 32-bit only;
24-bit files will raise on write.
"""

import math
import os
import struct
import sys

import numpy as np

TARGET_DB = -1.0
TARGET_AMPLITUDE = 10 ** (TARGET_DB / 20)

CLICK_KITS_DIR = os.path.normpath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "assets",
        "audio",
        "click_kits",
    )
)

# WAV format codes
WAV_FORMAT_PCM = 1
WAV_FORMAT_IEEE_FLOAT = 3


def _find_chunk(data: bytes, chunk_id: bytes, start: int = 12) -> tuple[int, int]:
    """Find a chunk in WAV data. Returns (data_offset, data_size)."""
    pos = start
    while pos < len(data) - 8:
        cid = data[pos : pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        if cid == chunk_id:
            return pos + 8, size
        pos += 8 + size
        if pos % 2 != 0:
            pos += 1
    raise ValueError(f"Chunk {chunk_id!r} not found")


def read_wav(filepath: str) -> tuple[np.ndarray, bytes]:
    """Read a WAV file and return (samples_float64, raw_file_bytes).

    Returns samples normalized to [-1.0, 1.0] regardless of source format.
    The raw bytes are kept so we can reconstruct the file preserving all
    metadata chunks.
    """
    with open(filepath, "rb") as f:
        raw = f.read()

    # Parse fmt chunk
    fmt_offset, fmt_size = _find_chunk(raw, b"fmt ")
    fmt_data = raw[fmt_offset : fmt_offset + fmt_size]
    audio_format = struct.unpack_from("<H", fmt_data, 0)[0]
    channels = struct.unpack_from("<H", fmt_data, 2)[0]
    sample_rate = struct.unpack_from("<I", fmt_data, 4)[0]
    bits_per_sample = struct.unpack_from("<H", fmt_data, 14)[0]

    # Parse data chunk
    data_offset, data_size = _find_chunk(raw, b"data")
    pcm_data = raw[data_offset : data_offset + data_size]

    if audio_format == WAV_FORMAT_IEEE_FLOAT and bits_per_sample == 32:
        samples = np.frombuffer(pcm_data, dtype=np.float32).astype(np.float64)
    elif audio_format == WAV_FORMAT_PCM and bits_per_sample == 16:
        samples = np.frombuffer(pcm_data, dtype=np.int16).astype(np.float64) / 32767.0
    elif audio_format == WAV_FORMAT_PCM and bits_per_sample == 24:
        n_samples = len(pcm_data) // 3
        samples = np.zeros(n_samples, dtype=np.float64)
        for i in range(n_samples):
            b = pcm_data[i * 3 : i * 3 + 3]
            pad = b"\xff" if b[2] & 0x80 else b"\x00"
            value = struct.unpack("<i", b + pad)[0]
            samples[i] = value / 8388607.0
    elif audio_format == WAV_FORMAT_PCM and bits_per_sample == 32:
        samples = (
            np.frombuffer(pcm_data, dtype=np.int32).astype(np.float64) / 2147483647.0
        )
    else:
        raise ValueError(
            f"Unsupported WAV format: format={audio_format}, bits={bits_per_sample}"
        )

    return samples, raw


def write_wav_normalized(
    filepath: str, samples: np.ndarray, original_raw: bytes
) -> None:
    """Write normalized samples back, preserving the original WAV structure."""
    # Parse original format
    fmt_offset, fmt_size = _find_chunk(original_raw, b"fmt ")
    fmt_data = original_raw[fmt_offset : fmt_offset + fmt_size]
    audio_format = struct.unpack_from("<H", fmt_data, 0)[0]
    bits_per_sample = struct.unpack_from("<H", fmt_data, 14)[0]

    # Encode samples back to original format
    clipped = np.clip(samples, -1.0, 1.0)

    if audio_format == WAV_FORMAT_IEEE_FLOAT and bits_per_sample == 32:
        new_pcm = clipped.astype(np.float32).tobytes()
    elif audio_format == WAV_FORMAT_PCM and bits_per_sample == 16:
        new_pcm = (clipped * 32767.0).astype(np.int16).tobytes()
    elif audio_format == WAV_FORMAT_PCM and bits_per_sample == 32:
        new_pcm = (clipped * 2147483647.0).astype(np.int32).tobytes()
    else:
        raise ValueError("Cannot write back unsupported format")

    # Replace data chunk content in the original raw bytes
    data_offset, data_size = _find_chunk(original_raw, b"data")
    new_raw = bytearray(original_raw[:data_offset])
    new_raw.extend(new_pcm)
    # Skip old data, append anything after
    after_data = data_offset + data_size
    if after_data < len(original_raw):
        new_raw.extend(original_raw[after_data:])

    # Fix data chunk size
    data_chunk_header_offset = data_offset - 8
    struct.pack_into("<I", new_raw, data_chunk_header_offset + 4, len(new_pcm))

    # Fix RIFF size
    struct.pack_into("<I", new_raw, 4, len(new_raw) - 8)

    with open(filepath, "wb") as f:
        f.write(new_raw)


def process_kit(kit_dir: str) -> None:
    """Normalize all WAV files in a kit directory."""
    kit_name = os.path.basename(kit_dir)
    wav_files = sorted(f for f in os.listdir(kit_dir) if f.endswith(".wav"))

    if not wav_files:
        print(f"  {kit_name}: no WAV files found, skipping")
        return

    # Phase 1: read all files and find global peak.
    file_data: list[tuple[str, np.ndarray, bytes]] = []
    global_peak = 0.0

    for wav_file in wav_files:
        filepath = os.path.join(kit_dir, wav_file)
        samples, raw = read_wav(filepath)
        peak = float(np.max(np.abs(samples)))
        file_data.append((filepath, samples, raw))
        global_peak = max(global_peak, peak)

    if global_peak == 0:
        print(f"  {kit_name}: all-silent kit, skipping")
        return

    gain = TARGET_AMPLITUDE / global_peak
    gain_db = 20 * math.log10(gain) if gain > 0 else -100
    peak_db = 20 * math.log10(global_peak) if global_peak > 0 else -100

    print(f"  {kit_name}: peak={peak_db:+.1f}dB, gain={gain_db:+.1f}dB")

    # Phase 2: apply gain and write back.
    for filepath, samples, raw in file_data:
        normalized = samples * gain
        write_wav_normalized(filepath, normalized, raw)
        new_peak = float(np.max(np.abs(normalized)))
        new_peak_db = 20 * math.log10(new_peak) if new_peak > 0 else -100
        print(f"    {os.path.basename(filepath):40s} -> peak={new_peak_db:+.1f}dB")


def main() -> None:
    if not os.path.isdir(CLICK_KITS_DIR):
        print(
            f"Error: click kits directory not found: {CLICK_KITS_DIR}", file=sys.stderr
        )
        sys.exit(1)

    print(f"Normalizing click kits to {TARGET_DB:+.1f} dBFS peak")
    print(f"Directory: {CLICK_KITS_DIR}\n")

    kit_dirs = sorted(
        os.path.join(CLICK_KITS_DIR, d)
        for d in os.listdir(CLICK_KITS_DIR)
        if os.path.isdir(os.path.join(CLICK_KITS_DIR, d)) and not d.startswith(".")
    )

    for kit_dir in kit_dirs:
        process_kit(kit_dir)

    print("\nDone.")


if __name__ == "__main__":
    main()
