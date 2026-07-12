#!/usr/bin/env python3
# Derive the Ed25519 public key from a private seed using ONLY the Python stdlib.
#
# Why this exists (supply-chain hardening):
#   The release job's "verify signing key" step is the ONLY place a third-party
#   package (pip `cryptography` + its transitive `cffi`) was downloaded and executed
#   in the SAME job where the Sparkle signing private key lives in the environment.
#   A compromised PyPI/index serving a malicious wheel could read that key. This
#   script removes that surface entirely: no pip, no network fetch, no binary deps.
#
# Scope & safety:
#   This performs ONE public operation — derive a PUBLIC key from a seed and print it
#   for an equality check against the app's embedded SUPublicEDKey. It never signs and
#   never emits the private key. It cannot fail open: malformed input (bad base64 or a
#   non-32-byte secret) RAISES and fails the release, and a mismatched key yields a
#   MISMATCH that fails the release — a wrong key can never be accepted before publish.
#   Correctness is pinned by the RFC 8032 test vectors below, which run on every
#   invocation before the real derivation (so a broken interpreter fails the release).
#
# Algorithm: RFC 8032 §5.1 / Appendix-A reference (edwards25519), verbatim math.

import base64
import hashlib
import os
import sys

# Prime of the base field Z_p and curve/group constants.
p = 2**255 - 19
q = 2**252 + 27742317777372353535851937790883648493  # group order (unused for pub derivation)


def sha512(s: bytes) -> bytes:
    return hashlib.sha512(s).digest()


def modp_inv(x: int) -> int:
    return pow(x, p - 2, p)


d = -121665 * modp_inv(121666) % p
modp_sqrt_m1 = pow(2, (p - 1) // 4, p)


def recover_x(y: int, sign: int):
    if y >= p:
        return None
    x2 = (y * y - 1) * modp_inv(d * y * y + 1)
    if x2 % p == 0:
        return None if sign else 0
    x = pow(x2, (p + 3) // 8, p)
    if (x * x - x2) % p != 0:
        x = x * modp_sqrt_m1 % p
    if (x * x - x2) % p != 0:
        return None
    if (x & 1) != sign:
        x = p - x
    return x


# Base point B, held in extended coordinates (X, Y, Z, T) with x=X/Z, y=Y/Z, xy=T/Z.
g_y = 4 * modp_inv(5) % p
g_x = recover_x(g_y, 0)
assert g_x is not None  # base point x is well-defined (invariant of edwards25519)
G = (g_x, g_y, 1, g_x * g_y % p)


def point_add(P, Q):
    A = (P[1] - P[0]) * (Q[1] - Q[0]) % p
    B = (P[1] + P[0]) * (Q[1] + Q[0]) % p
    C = 2 * P[3] * Q[3] * d % p
    D = 2 * P[2] * Q[2] % p
    E, F, Gc, H = B - A, D - C, D + C, B + A
    return (E * F % p, Gc * H % p, F * Gc % p, E * H % p)


def point_mul(s: int, P):
    Q = (0, 1, 1, 0)  # neutral element
    while s > 0:
        if s & 1:
            Q = point_add(Q, P)
        P = point_add(P, P)
        s >>= 1
    return Q


def point_compress(P) -> bytes:
    zinv = modp_inv(P[2])
    x = P[0] * zinv % p
    y = P[1] * zinv % p
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def secret_to_public(seed: bytes) -> bytes:
    if len(seed) != 32:
        raise ValueError(f"seed must be 32 bytes, got {len(seed)}")
    h = sha512(seed)
    a = int.from_bytes(h[:32], "little")
    a &= (1 << 254) - 8   # clamp: clear low 3 bits
    a |= (1 << 254)       # clamp: set bit 254, clear bit 255
    return point_compress(point_mul(a, G))


# RFC 8032 §7.1 test vectors (seed hex, expected public-key hex). Ground truth for
# correctness — identical to what pyca/cryptography produces.
_RFC8032_VECTORS = [
    ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
     "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"),
    ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
     "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"),
    ("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
     "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"),
]


def _selftest() -> None:
    for seed_hex, pub_hex in _RFC8032_VECTORS:
        got = secret_to_public(bytes.fromhex(seed_hex)).hex()
        if got != pub_hex:
            raise SystemExit(f"::error::ed25519 self-test FAILED: seed {seed_hex} -> {got} != {pub_hex}")


def _seed_from_b64(b64: str) -> bytes:
    # Strict base64: reject stray/invalid characters instead of silently dropping them.
    # (Default b64decode ignores garbage, so "<valid>!!!!" would decode the same and let
    #  malformed input slip through the key check.)
    raw = base64.b64decode(b64.strip(), validate=True)
    # Sparkle 2.9.3's key contract (common_cli/Secret.swift): a 32-byte private seed
    # (current format — what `generate_keys` now produces and what we use) or a legacy
    # 96-byte secret (64-byte orlp key || 32-byte public). A bare 64-byte value is NOT a
    # valid Sparkle secret. We only ship 32-byte seeds; reject anything else loudly so the
    # gate can never "match" against truncated or padded bytes.
    if len(raw) != 32:
        raise ValueError(
            f"expected a 32-byte Ed25519 seed (Sparkle 2.9.3 current format), got {len(raw)} bytes; "
            "legacy 96-byte Sparkle secrets are not supported"
        )
    return raw


def main(argv) -> int:
    # Always verify the implementation against RFC vectors before trusting a derivation.
    _selftest()

    if len(argv) > 1 and argv[1] == "--selftest":
        print("ed25519 self-test OK (RFC 8032 vectors)")
        return 0

    # Input: base64 private key from $SPARKLE_ED_PRIVATE_KEY (default) or argv[1].
    b64 = argv[1] if len(argv) > 1 else os.environ.get("SPARKLE_ED_PRIVATE_KEY", "")
    if not b64:
        raise SystemExit("::error::no private key: set SPARKLE_ED_PRIVATE_KEY or pass base64 as arg1")
    # Turn malformed input into a clean CI error annotation (fail-closed) rather than a
    # raw traceback. binascii.Error (strict base64) is a ValueError subclass, so this covers
    # both bad-base64 and wrong-length. A nonzero exit blocks the release under `set -e`.
    try:
        pub = secret_to_public(_seed_from_b64(b64))
    except ValueError as e:
        raise SystemExit(f"::error::invalid Sparkle private key: {e}")
    print(base64.b64encode(pub).decode())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
