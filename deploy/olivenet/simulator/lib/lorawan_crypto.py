"""
LoRaWAN Cryptography Library

Implements LoRaWAN 1.0.x cryptographic operations:
- AES-128-CMAC for MIC calculation
- AES-128-ECB for payload encryption/decryption
- Join Accept decryption
- Session key derivation (NwkSKey, AppSKey)

Reference: LoRaWAN 1.0.3 Specification, Section 4 (MAC Frame Formats)
"""

import os
import struct
from typing import Tuple, Optional
from Crypto.Cipher import AES
from Crypto.Hash import CMAC


# Direction constants for encryption
DIR_UPLINK = 0
DIR_DOWNLINK = 1


def compute_mic(key: bytes, data: bytes) -> bytes:
    """
    Compute AES-128-CMAC Message Integrity Code.

    Args:
        key: 16-byte AES key
        data: Data to compute MIC over

    Returns:
        4-byte MIC (first 4 bytes of CMAC)

    Reference: LoRaWAN 1.0.3 Spec, Section 4.4 (Message Integrity Code)
    """
    if len(key) != 16:
        raise ValueError("Key must be 16 bytes")

    cobj = CMAC.new(key, ciphermod=AES)
    cobj.update(data)
    return cobj.digest()[:4]


def compute_join_request_mic(
    app_key: bytes,
    mhdr: int,
    join_eui: bytes,
    dev_eui: bytes,
    dev_nonce: int
) -> bytes:
    """
    Compute MIC for Join Request message.

    MIC = cmac[0:3](AppKey, MHDR | JoinEUI | DevEUI | DevNonce)

    Args:
        app_key: 16-byte Application Key
        mhdr: MAC Header byte
        join_eui: 8-byte Join EUI (little-endian)
        dev_eui: 8-byte Device EUI (little-endian)
        dev_nonce: 2-byte Device Nonce

    Returns:
        4-byte MIC

    Reference: LoRaWAN 1.0.3 Spec, Section 6.2.4
    """
    # Build the message: MHDR | JoinEUI | DevEUI | DevNonce
    msg = struct.pack('B', mhdr)  # 1 byte MHDR
    msg += join_eui[::-1]  # JoinEUI in little-endian (reverse for wire format)
    msg += dev_eui[::-1]   # DevEUI in little-endian
    msg += struct.pack('<H', dev_nonce)  # DevNonce little-endian

    return compute_mic(app_key, msg)


def compute_uplink_mic(
    nwk_s_key: bytes,
    dev_addr: bytes,
    fcnt_up: int,
    mhdr: int,
    fhdr: bytes,
    fport: Optional[int],
    frm_payload: bytes
) -> bytes:
    """
    Compute MIC for uplink data message (LoRaWAN 1.0.x).

    MIC = cmac[0:3](NwkSKey, B0 | msg)

    B0 = 0x49 | 4×0x00 | Dir | DevAddr | FCntUp | 0x00 | len(msg)

    Args:
        nwk_s_key: 16-byte Network Session Key
        dev_addr: 4-byte Device Address (little-endian)
        fcnt_up: 32-bit uplink frame counter
        mhdr: MAC Header byte
        fhdr: Frame Header bytes (FCtrl, FCnt, FOpts)
        fport: Frame Port (None if no payload)
        frm_payload: Encrypted frame payload

    Returns:
        4-byte MIC

    Reference: LoRaWAN 1.0.3 Spec, Section 4.4
    """
    # Build the message: MHDR | FHDR | FPort | FRMPayload
    msg = struct.pack('B', mhdr)
    msg += fhdr
    if fport is not None:
        msg += struct.pack('B', fport)
        msg += frm_payload

    # Build B0 block
    b0 = struct.pack(
        '<BBBBBBBBIBB',
        0x49,           # B0 constant
        0x00, 0x00, 0x00, 0x00,  # 4 zeros
        DIR_UPLINK,     # Direction (uplink = 0)
        dev_addr[0], dev_addr[1], dev_addr[2], dev_addr[3],  # DevAddr LE
        fcnt_up & 0xFFFFFFFF,  # FCntUp
        0x00,           # 0x00
        len(msg)        # Length
    )

    return compute_mic(nwk_s_key, b0 + msg)


def compute_downlink_mic(
    nwk_s_key: bytes,
    dev_addr: bytes,
    fcnt_down: int,
    mhdr: int,
    fhdr: bytes,
    fport: Optional[int],
    frm_payload: bytes
) -> bytes:
    """
    Compute MIC for downlink data message (LoRaWAN 1.0.x).

    Same as uplink but with Dir=1.

    Args:
        nwk_s_key: 16-byte Network Session Key
        dev_addr: 4-byte Device Address
        fcnt_down: 32-bit downlink frame counter
        mhdr: MAC Header byte
        fhdr: Frame Header bytes
        fport: Frame Port (None if no payload)
        frm_payload: Encrypted frame payload

    Returns:
        4-byte MIC
    """
    # Build the message
    msg = struct.pack('B', mhdr)
    msg += fhdr
    if fport is not None:
        msg += struct.pack('B', fport)
        msg += frm_payload

    # Build B0 block
    b0 = struct.pack(
        '<BBBBBBBBBIBB',
        0x49,
        0x00, 0x00, 0x00, 0x00,
        DIR_DOWNLINK,
        dev_addr[0], dev_addr[1], dev_addr[2], dev_addr[3],
        fcnt_down & 0xFFFFFFFF,
        0x00,
        len(msg)
    )

    return compute_mic(nwk_s_key, b0 + msg)


def encrypt_frm_payload(
    key: bytes,
    dev_addr: bytes,
    fcnt: int,
    direction: int,
    payload: bytes
) -> bytes:
    """
    Encrypt/decrypt FRMPayload using AES-128 counter mode.

    Uses AES in ECB mode as a block cipher, with custom counter generation
    per LoRaWAN specification.

    Args:
        key: 16-byte key (AppSKey for FPort>0, NwkSKey for FPort=0)
        dev_addr: 4-byte Device Address (little-endian)
        fcnt: Frame counter
        direction: 0=uplink, 1=downlink
        payload: Plaintext/ciphertext to encrypt/decrypt

    Returns:
        Encrypted/decrypted payload

    Reference: LoRaWAN 1.0.3 Spec, Section 4.3.3
    """
    if len(key) != 16:
        raise ValueError("Key must be 16 bytes")

    if not payload:
        return b''

    cipher = AES.new(key, AES.MODE_ECB)

    # Calculate number of blocks needed
    k = (len(payload) + 15) // 16

    # Generate S blocks
    s_blocks = b''
    for i in range(1, k + 1):
        # Ai block: 0x01 | 4×0x00 | Dir | DevAddr | FCnt | 0x00 | i
        ai = struct.pack(
            '<BBBBBBBBBIB',
            0x01,
            0x00, 0x00, 0x00, 0x00,
            direction,
            dev_addr[0], dev_addr[1], dev_addr[2], dev_addr[3],
            fcnt & 0xFFFFFFFF,
            0x00,
            i
        )
        si = cipher.encrypt(ai)
        s_blocks += si

    # XOR payload with S
    result = bytes(a ^ b for a, b in zip(payload, s_blocks[:len(payload)]))

    return result


def decrypt_join_accept(app_key: bytes, encrypted: bytes) -> bytes:
    """
    Decrypt Join Accept message.

    Join Accept is encrypted with AES-128-ECB "decrypt" operation
    (which means server uses AES encrypt, device uses AES decrypt).

    Args:
        app_key: 16-byte Application Key
        encrypted: Encrypted Join Accept (excluding MHDR)

    Returns:
        Decrypted Join Accept payload

    Reference: LoRaWAN 1.0.3 Spec, Section 6.2.5
    """
    if len(app_key) != 16:
        raise ValueError("AppKey must be 16 bytes")

    # Join Accept can be 16 bytes (without CFList) or 32 bytes (with CFList)
    if len(encrypted) not in (16, 32):
        raise ValueError(f"Invalid Join Accept length: {len(encrypted)}")

    cipher = AES.new(app_key, AES.MODE_ECB)

    # Device decrypts using AES encrypt (reverse of server's encrypt with decrypt)
    decrypted = b''
    for i in range(0, len(encrypted), 16):
        block = encrypted[i:i+16]
        decrypted += cipher.encrypt(block)

    return decrypted


def derive_session_keys(
    app_key: bytes,
    join_nonce: bytes,
    net_id: bytes,
    dev_nonce: int
) -> Tuple[bytes, bytes]:
    """
    Derive session keys from Join Accept parameters.

    NwkSKey = aes128_encrypt(AppKey, 0x01 | JoinNonce | NetID | DevNonce | pad16)
    AppSKey = aes128_encrypt(AppKey, 0x02 | JoinNonce | NetID | DevNonce | pad16)

    Args:
        app_key: 16-byte Application Key
        join_nonce: 3-byte Join Nonce (AppNonce in LoRaWAN 1.0)
        net_id: 3-byte Network ID
        dev_nonce: 2-byte Device Nonce

    Returns:
        Tuple of (NwkSKey, AppSKey), each 16 bytes

    Reference: LoRaWAN 1.0.3 Spec, Section 6.2.5
    """
    if len(app_key) != 16:
        raise ValueError("AppKey must be 16 bytes")
    if len(join_nonce) != 3:
        raise ValueError("JoinNonce must be 3 bytes")
    if len(net_id) != 3:
        raise ValueError("NetID must be 3 bytes")

    cipher = AES.new(app_key, AES.MODE_ECB)

    # Build key derivation blocks
    dev_nonce_bytes = struct.pack('<H', dev_nonce)
    padding = bytes(7)  # Pad to 16 bytes

    # NwkSKey: 0x01 | JoinNonce | NetID | DevNonce | pad
    nwk_block = bytes([0x01]) + join_nonce + net_id + dev_nonce_bytes + padding
    nwk_s_key = cipher.encrypt(nwk_block)

    # AppSKey: 0x02 | JoinNonce | NetID | DevNonce | pad
    app_block = bytes([0x02]) + join_nonce + net_id + dev_nonce_bytes + padding
    app_s_key = cipher.encrypt(app_block)

    return (nwk_s_key, app_s_key)


def generate_dev_nonce() -> int:
    """
    Generate a random 2-byte device nonce.

    Returns:
        Random 16-bit integer
    """
    return struct.unpack('<H', os.urandom(2))[0]


def aes_encrypt_block(key: bytes, data: bytes) -> bytes:
    """
    AES-128-ECB encrypt a single 16-byte block.

    Args:
        key: 16-byte AES key
        data: 16-byte data block

    Returns:
        16-byte encrypted block
    """
    if len(key) != 16 or len(data) != 16:
        raise ValueError("Key and data must be 16 bytes")

    cipher = AES.new(key, AES.MODE_ECB)
    return cipher.encrypt(data)


def verify_join_accept_mic(
    app_key: bytes,
    mhdr: int,
    decrypted_payload: bytes
) -> bool:
    """
    Verify MIC of decrypted Join Accept.

    Args:
        app_key: 16-byte Application Key
        mhdr: MAC Header byte (0x20 for Join Accept)
        decrypted_payload: Decrypted Join Accept (JoinNonce|NetID|DevAddr|DLSettings|RxDelay|[CFList]|MIC)

    Returns:
        True if MIC is valid
    """
    # MIC is last 4 bytes
    mic_received = decrypted_payload[-4:]
    payload_without_mic = decrypted_payload[:-4]

    # Compute MIC: cmac[0:3](AppKey, MHDR | payload_without_mic)
    msg = struct.pack('B', mhdr) + payload_without_mic
    mic_computed = compute_mic(app_key, msg)

    return mic_received == mic_computed


# MType values for MHDR
class MType:
    """LoRaWAN Message Types (MType field in MHDR)"""
    JOIN_REQUEST = 0
    JOIN_ACCEPT = 1
    UNCONFIRMED_DATA_UP = 2
    UNCONFIRMED_DATA_DOWN = 3
    CONFIRMED_DATA_UP = 4
    CONFIRMED_DATA_DOWN = 5
    REJOIN_REQUEST = 6
    PROPRIETARY = 7


def build_mhdr(mtype: int, major: int = 0) -> int:
    """
    Build MAC Header byte.

    MHDR = MType(3 bits) | RFU(3 bits) | Major(2 bits)

    Args:
        mtype: Message type (0-7)
        major: LoRaWAN major version (0 for LoRaWAN R1)

    Returns:
        1-byte MHDR value
    """
    return ((mtype & 0x07) << 5) | (major & 0x03)


def parse_mhdr(mhdr: int) -> Tuple[int, int]:
    """
    Parse MAC Header byte.

    Args:
        mhdr: MHDR byte value

    Returns:
        Tuple of (mtype, major)
    """
    mtype = (mhdr >> 5) & 0x07
    major = mhdr & 0x03
    return (mtype, major)
