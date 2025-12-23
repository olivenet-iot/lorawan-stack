"""
Virtual LoRaWAN End Device

Simulates a LoRaWAN 1.0.x device capable of:
- OTAA (Over-The-Air Activation)
- ABP (Activation By Personalization)
- Uplink transmission
- Downlink reception
- MAC command handling

Reference: LoRaWAN 1.0.3 Specification
"""

import struct
import base64
from dataclasses import dataclass, field
from typing import Optional, Tuple, Dict, Any
from enum import IntEnum

from .lorawan_crypto import (
    compute_join_request_mic,
    compute_uplink_mic,
    compute_downlink_mic,
    encrypt_frm_payload,
    decrypt_join_accept,
    derive_session_keys,
    verify_join_accept_mic,
    generate_dev_nonce,
    build_mhdr,
    parse_mhdr,
    MType,
    DIR_UPLINK,
    DIR_DOWNLINK,
)


class FCtrlBits(IntEnum):
    """FCtrl field bit positions"""
    ADR = 0x80
    ADR_ACK_REQ = 0x40
    ACK = 0x20
    CLASS_B = 0x10  # RFU in uplink, ClassB in downlink
    FOPTS_LEN_MASK = 0x0F


@dataclass
class DeviceSession:
    """Active device session state"""
    dev_addr: bytes          # 4 bytes
    nwk_s_key: bytes         # 16 bytes
    app_s_key: bytes         # 16 bytes
    fcnt_up: int = 0         # Uplink frame counter
    fcnt_down: int = 0       # Downlink frame counter
    rx1_delay: int = 1       # RX1 delay in seconds
    rx1_dr_offset: int = 0   # RX1 data rate offset
    rx2_dr: int = 0          # RX2 data rate
    rx2_freq: float = 869.525  # RX2 frequency in MHz


class VirtualDevice:
    """
    Virtual LoRaWAN End Device.

    Simulates a LoRaWAN 1.0.x Class A device with OTAA/ABP support.
    """

    def __init__(
        self,
        dev_eui: bytes,
        join_eui: bytes,
        app_key: bytes,
        lorawan_version: str = "1.0.3",
    ):
        """
        Initialize a virtual device.

        Args:
            dev_eui: 8-byte Device EUI
            join_eui: 8-byte Join EUI (AppEUI in LoRaWAN 1.0)
            app_key: 16-byte Application Key
            lorawan_version: LoRaWAN version string
        """
        if len(dev_eui) != 8:
            raise ValueError("DevEUI must be 8 bytes")
        if len(join_eui) != 8:
            raise ValueError("JoinEUI must be 8 bytes")
        if len(app_key) != 16:
            raise ValueError("AppKey must be 16 bytes")

        self.dev_eui = dev_eui
        self.join_eui = join_eui
        self.app_key = app_key
        self.lorawan_version = lorawan_version

        # Session state (populated after join)
        self.session: Optional[DeviceSession] = None

        # Device nonce tracking (for OTAA replay protection)
        self._dev_nonce_counter = 0
        self._last_dev_nonce: Optional[int] = None

        # ADR settings
        self.adr_enabled = True
        self.data_rate = 5  # SF7BW125
        self.tx_power = 14  # dBm

        # Pending ACK tracking
        self._awaiting_ack = False
        self._pending_confirmed_fcnt: Optional[int] = None

    @property
    def is_joined(self) -> bool:
        """Check if device has an active session"""
        return self.session is not None

    @property
    def dev_addr(self) -> Optional[bytes]:
        """Get device address (None if not joined)"""
        return self.session.dev_addr if self.session else None

    def build_join_request(self) -> bytes:
        """
        Build a Join Request message.

        Format: MHDR(1) | JoinEUI(8) | DevEUI(8) | DevNonce(2) | MIC(4)

        Returns:
            Complete PHY payload for Join Request
        """
        # Generate new DevNonce
        self._dev_nonce_counter += 1
        dev_nonce = self._dev_nonce_counter & 0xFFFF
        self._last_dev_nonce = dev_nonce

        # Build MHDR
        mhdr = build_mhdr(MType.JOIN_REQUEST)

        # Compute MIC
        mic = compute_join_request_mic(
            self.app_key,
            mhdr,
            self.join_eui,
            self.dev_eui,
            dev_nonce
        )

        # Build message: MHDR | JoinEUI(LE) | DevEUI(LE) | DevNonce(LE) | MIC
        phy_payload = struct.pack('B', mhdr)
        phy_payload += self.join_eui[::-1]  # Little-endian on wire
        phy_payload += self.dev_eui[::-1]   # Little-endian on wire
        phy_payload += struct.pack('<H', dev_nonce)
        phy_payload += mic

        return phy_payload

    def process_join_accept(self, encrypted_payload: bytes) -> bool:
        """
        Process a Join Accept message.

        Args:
            encrypted_payload: Complete encrypted Join Accept (including MHDR)

        Returns:
            True if join was successful

        Raises:
            ValueError: If decryption or MIC verification fails
        """
        if len(encrypted_payload) < 17:  # MHDR(1) + encrypted(16+)
            raise ValueError("Join Accept too short")

        mhdr = encrypted_payload[0]
        mtype, major = parse_mhdr(mhdr)

        if mtype != MType.JOIN_ACCEPT:
            raise ValueError(f"Not a Join Accept: MType={mtype}")

        # Decrypt payload (excluding MHDR)
        encrypted = encrypted_payload[1:]
        decrypted = decrypt_join_accept(self.app_key, encrypted)

        # Verify MIC
        if not verify_join_accept_mic(self.app_key, mhdr, decrypted):
            raise ValueError("Join Accept MIC verification failed")

        # Parse decrypted payload
        # JoinNonce(3) | NetID(3) | DevAddr(4) | DLSettings(1) | RxDelay(1) | [CFList(16)] | MIC(4)
        join_nonce = decrypted[0:3]
        net_id = decrypted[3:6]
        dev_addr = decrypted[6:10]
        dl_settings = decrypted[10]
        rx_delay = decrypted[11]

        # Check for CFList
        if len(decrypted) == 16 + 4:  # No CFList
            cflist = None
        elif len(decrypted) == 16 + 16 + 4:  # With CFList
            cflist = decrypted[12:28]
        else:
            raise ValueError(f"Invalid Join Accept length: {len(decrypted)}")

        # Parse DLSettings
        rx1_dr_offset = (dl_settings >> 4) & 0x07
        rx2_dr = dl_settings & 0x0F

        # RxDelay: 0 means 1 second
        if rx_delay == 0:
            rx_delay = 1

        # Derive session keys
        nwk_s_key, app_s_key = derive_session_keys(
            self.app_key,
            join_nonce,
            net_id,
            self._last_dev_nonce
        )

        # Create session
        self.session = DeviceSession(
            dev_addr=dev_addr,
            nwk_s_key=nwk_s_key,
            app_s_key=app_s_key,
            fcnt_up=0,
            fcnt_down=0,
            rx1_delay=rx_delay,
            rx1_dr_offset=rx1_dr_offset,
            rx2_dr=rx2_dr,
        )

        return True

    def activate_abp(
        self,
        dev_addr: bytes,
        nwk_s_key: bytes,
        app_s_key: bytes,
        fcnt_up: int = 0,
        fcnt_down: int = 0
    ):
        """
        Activate device using ABP (Activation By Personalization).

        Args:
            dev_addr: 4-byte device address
            nwk_s_key: 16-byte network session key
            app_s_key: 16-byte application session key
            fcnt_up: Initial uplink frame counter
            fcnt_down: Initial downlink frame counter
        """
        if len(dev_addr) != 4:
            raise ValueError("DevAddr must be 4 bytes")
        if len(nwk_s_key) != 16:
            raise ValueError("NwkSKey must be 16 bytes")
        if len(app_s_key) != 16:
            raise ValueError("AppSKey must be 16 bytes")

        self.session = DeviceSession(
            dev_addr=dev_addr,
            nwk_s_key=nwk_s_key,
            app_s_key=app_s_key,
            fcnt_up=fcnt_up,
            fcnt_down=fcnt_down,
        )

    def build_uplink(
        self,
        port: int,
        payload: bytes,
        confirmed: bool = False,
        fopts: bytes = b''
    ) -> bytes:
        """
        Build an uplink data message.

        Format: MHDR(1) | DevAddr(4) | FCtrl(1) | FCnt(2) | [FOpts(0-15)] | [FPort(1)] | [FRMPayload] | MIC(4)

        Args:
            port: FPort (1-223 for application data)
            payload: Application payload (will be encrypted)
            confirmed: Use confirmed uplink (requires ACK)
            fopts: MAC commands in FOpts field

        Returns:
            Complete PHY payload

        Raises:
            RuntimeError: If device is not joined
        """
        if not self.session:
            raise RuntimeError("Device not joined")

        if port < 0 or port > 223:
            raise ValueError("FPort must be 0-223")

        if len(fopts) > 15:
            raise ValueError("FOpts must be 0-15 bytes")

        # Encrypt payload
        key = self.session.nwk_s_key if port == 0 else self.session.app_s_key
        encrypted_payload = encrypt_frm_payload(
            key,
            self.session.dev_addr,
            self.session.fcnt_up,
            DIR_UPLINK,
            payload
        )

        # Build MHDR
        mtype = MType.CONFIRMED_DATA_UP if confirmed else MType.UNCONFIRMED_DATA_UP
        mhdr = build_mhdr(mtype)

        # Build FCtrl
        fctrl = len(fopts) & 0x0F
        if self.adr_enabled:
            fctrl |= FCtrlBits.ADR
        if self._awaiting_ack:
            fctrl |= FCtrlBits.ADR_ACK_REQ

        # Build FHDR: DevAddr(4) | FCtrl(1) | FCnt(2) | [FOpts]
        fhdr = self.session.dev_addr  # Little-endian on wire (already stored that way)
        fhdr += struct.pack('B', fctrl)
        fhdr += struct.pack('<H', self.session.fcnt_up & 0xFFFF)
        fhdr += fopts

        # Compute MIC
        mic = compute_uplink_mic(
            self.session.nwk_s_key,
            self.session.dev_addr,
            self.session.fcnt_up,
            mhdr,
            fhdr,
            port,
            encrypted_payload
        )

        # Build complete message
        phy_payload = struct.pack('B', mhdr)
        phy_payload += fhdr
        phy_payload += struct.pack('B', port)
        phy_payload += encrypted_payload
        phy_payload += mic

        # Update state
        if confirmed:
            self._awaiting_ack = True
            self._pending_confirmed_fcnt = self.session.fcnt_up

        self.session.fcnt_up += 1

        return phy_payload

    def process_downlink(self, phy_payload: bytes) -> Tuple[Optional[bytes], Dict[str, Any]]:
        """
        Process a downlink message.

        Args:
            phy_payload: Complete PHY payload

        Returns:
            Tuple of (decrypted_payload, info_dict)
            info_dict contains: ack, pending, fport, mac_commands

        Raises:
            RuntimeError: If device is not joined
            ValueError: If message is invalid or MIC fails
        """
        if not self.session:
            raise RuntimeError("Device not joined")

        if len(phy_payload) < 12:  # Minimum: MHDR(1) + FHDR(7) + MIC(4)
            raise ValueError("Downlink too short")

        # Parse MHDR
        mhdr = phy_payload[0]
        mtype, major = parse_mhdr(mhdr)

        if mtype not in (MType.UNCONFIRMED_DATA_DOWN, MType.CONFIRMED_DATA_DOWN):
            raise ValueError(f"Not a data downlink: MType={mtype}")

        # Parse FHDR
        dev_addr = phy_payload[1:5]
        fctrl = phy_payload[5]
        fcnt_down = struct.unpack('<H', phy_payload[6:8])[0]

        # Verify DevAddr
        if dev_addr != self.session.dev_addr:
            raise ValueError("DevAddr mismatch")

        # Parse FCtrl
        adr = bool(fctrl & FCtrlBits.ADR)
        ack = bool(fctrl & FCtrlBits.ACK)
        pending = bool(fctrl & FCtrlBits.CLASS_B)  # FPending in downlink
        fopts_len = fctrl & FCtrlBits.FOPTS_LEN_MASK

        # Extract FOpts
        fhdr_len = 7 + fopts_len
        fhdr = phy_payload[1:1 + fhdr_len]
        fopts = phy_payload[8:8 + fopts_len] if fopts_len > 0 else b''

        # Extract MIC
        mic_received = phy_payload[-4:]

        # Check if there's FPort and FRMPayload
        has_payload = len(phy_payload) > 1 + fhdr_len + 4

        if has_payload:
            fport = phy_payload[1 + fhdr_len]
            encrypted_payload = phy_payload[1 + fhdr_len + 1:-4]
        else:
            fport = None
            encrypted_payload = b''

        # Verify MIC (using full 32-bit FCnt for internal tracking)
        full_fcnt = (self.session.fcnt_down & 0xFFFF0000) | fcnt_down
        if fcnt_down < (self.session.fcnt_down & 0xFFFF):
            # Counter rolled over
            full_fcnt += 0x10000

        mic_computed = compute_downlink_mic(
            self.session.nwk_s_key,
            self.session.dev_addr,
            full_fcnt,
            mhdr,
            fhdr,
            fport,
            encrypted_payload
        )

        if mic_received != mic_computed:
            raise ValueError("Downlink MIC verification failed")

        # Update FCnt
        self.session.fcnt_down = full_fcnt + 1

        # Decrypt payload
        decrypted_payload = None
        if has_payload and encrypted_payload:
            key = self.session.nwk_s_key if fport == 0 else self.session.app_s_key
            decrypted_payload = encrypt_frm_payload(
                key,
                self.session.dev_addr,
                full_fcnt,
                DIR_DOWNLINK,
                encrypted_payload
            )

        # Handle ACK
        if ack and self._awaiting_ack:
            self._awaiting_ack = False
            self._pending_confirmed_fcnt = None

        # Build info
        info = {
            'ack': ack,
            'pending': pending,
            'fport': fport,
            'mac_commands': fopts,
            'adr': adr,
            'fcnt_down': full_fcnt,
            'confirmed': mtype == MType.CONFIRMED_DATA_DOWN,
        }

        return (decrypted_payload, info)

    def session_info(self) -> Dict[str, Any]:
        """Get current session information"""
        if not self.session:
            return {'joined': False}

        return {
            'joined': True,
            'dev_addr': self.session.dev_addr.hex().upper(),
            'fcnt_up': self.session.fcnt_up,
            'fcnt_down': self.session.fcnt_down,
            'rx1_delay': self.session.rx1_delay,
            'rx1_dr_offset': self.session.rx1_dr_offset,
            'rx2_dr': self.session.rx2_dr,
        }

    def reset_session(self):
        """Reset device session (simulate power cycle)"""
        self.session = None
        self._awaiting_ack = False
        self._pending_confirmed_fcnt = None


def eui_from_string(eui_str: str) -> bytes:
    """Convert EUI string to bytes (e.g., '70B3D57ED0000001' -> bytes)"""
    eui_str = eui_str.replace(':', '').replace('-', '').upper()
    return bytes.fromhex(eui_str)


def key_from_string(key_str: str) -> bytes:
    """Convert key string to bytes"""
    key_str = key_str.replace(' ', '').upper()
    return bytes.fromhex(key_str)


def create_device_from_config(config: Dict[str, Any]) -> VirtualDevice:
    """Create a VirtualDevice from configuration dictionary"""
    return VirtualDevice(
        dev_eui=eui_from_string(config['dev_eui']),
        join_eui=eui_from_string(config.get('join_eui', config.get('app_eui', '0000000000000000'))),
        app_key=key_from_string(config['app_key']),
        lorawan_version=config.get('lorawan_version', '1.0.3'),
    )
