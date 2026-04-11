import 'dart:math';

/// Crockford's Base32 alphabet (no I, L, O, U) — used by ULID.
const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Generates [ULID](https://github.com/ulid/spec) v1 strings.
///
/// Format: 26 characters of Crockford base32 = 10-char timestamp + 16-char
/// random. Lexicographically sortable, ms-precision, collision-free across
/// concurrent generators (random part has 80 bits of entropy → ~6×10^11
/// IDs/ms before a 50% collision risk).
///
/// Why this exists: profile IDs were `DateTime.now().millisecondsSinceEpoch
/// .toString()`, so two profiles created in the same millisecond (which
/// happens during bulk URL imports) would collide and overwrite each
/// other's yaml/metadata. ULID guarantees uniqueness while still being
/// monotonically sortable.
class Ulid {
  Ulid._();

  static final Random _rng = Random.secure();
  static int _lastTime = 0;
  static final List<int> _lastRandom = List<int>.filled(10, 0);

  /// Returns a new 26-character ULID. Strictly monotonic within the same
  /// millisecond (the random part is incremented by 1 instead of being
  /// re-generated, so two ULIDs generated in the same ms still sort
  /// correctly).
  static String generate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final List<int> randomBytes;

    if (now == _lastTime) {
      // Monotonic increment of the previous random component
      randomBytes = List<int>.from(_lastRandom);
      _incrementRandom(randomBytes);
    } else {
      _lastTime = now;
      randomBytes = List<int>.generate(10, (_) => _rng.nextInt(256));
    }
    for (var i = 0; i < 10; i++) {
      _lastRandom[i] = randomBytes[i];
    }

    return _encodeTime(now) + _encodeRandom(randomBytes);
  }

  static void _incrementRandom(List<int> bytes) {
    for (var i = bytes.length - 1; i >= 0; i--) {
      if (bytes[i] < 0xff) {
        bytes[i]++;
        return;
      }
      bytes[i] = 0;
    }
    // Overflow: extremely unlikely (would require 2^80 IDs in 1ms)
  }

  /// Encode the 48-bit ms timestamp as 10 chars of Crockford base32.
  static String _encodeTime(int ms) {
    final buf = StringBuffer();
    var t = ms;
    final chars = List<String>.filled(10, '0');
    for (var i = 9; i >= 0; i--) {
      chars[i] = _crockford[t & 0x1f];
      t >>= 5;
    }
    for (final c in chars) {
      buf.write(c);
    }
    return buf.toString();
  }

  /// Encode 80 bits (10 bytes) of randomness as 16 chars of Crockford
  /// base32. We pack the bytes into a 80-bit integer and emit 16 5-bit
  /// groups, MSB first.
  static String _encodeRandom(List<int> bytes) {
    // Convert 10 bytes to 16 base32 characters (10*8 = 80 bits = 16*5)
    final buf = StringBuffer();
    var bitBuffer = 0;
    var bitsInBuffer = 0;
    for (final b in bytes) {
      bitBuffer = (bitBuffer << 8) | b;
      bitsInBuffer += 8;
      while (bitsInBuffer >= 5) {
        bitsInBuffer -= 5;
        final idx = (bitBuffer >> bitsInBuffer) & 0x1f;
        buf.write(_crockford[idx]);
      }
    }
    if (bitsInBuffer > 0) {
      final idx = (bitBuffer << (5 - bitsInBuffer)) & 0x1f;
      buf.write(_crockford[idx]);
    }
    return buf.toString();
  }
}
