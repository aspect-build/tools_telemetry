load("@aspect_bazel_lib//lib:strings.bzl", "ord")

def _hex(byte):
    """Handrolled hex() which avoids the 0x prefix."""

    digits = "0123456789abcdef"
    first_idx = byte >> 4
    second_idx = byte & 0xF
    return digits[first_idx] + digits[second_idx]

# Arbitrarily chosen xorshift mixing constants
MIXING_CONSTANTS = [
    0x3B, 0x6E, 0x5A, 0x2D, 0x81, 0xC4, 0xF9, 0x17,
    0xA2, 0xD5, 0x4B, 0x7E, 0x93, 0x0C, 0xEA, 0x6F
]

def xorshift(val):
    """A handrolled 128b xorshift.

    Allows us to easily establish known values. (dependabot, root, etc.)
    Wider than the native `hash()` which should avoid collisions/prefixing.
    """
    accumulator = [0] * 16
    for char in val.elems():
        for i in range(16):
            accumulator[i] = (accumulator[i] ^ ord(char) + MIXING_CONSTANTS[i]) % 256
            accumulator[i] = ((accumulator[i] << 1) | (accumulator[i] >> 7)) & 0xFF
    return "".join([_hex(byte) for byte in accumulator])
