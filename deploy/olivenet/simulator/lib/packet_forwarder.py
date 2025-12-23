"""
Semtech UDP Packet Forwarder Protocol Implementation

Implements the legacy UDP protocol used by most LoRaWAN gateways.

Protocol Reference:
https://github.com/Lora-net/packet_forwarder/blob/master/PROTOCOL.TXT

Message Types:
- PUSH_DATA (0x00): Gateway -> Server (uplink data)
- PUSH_ACK  (0x01): Server -> Gateway (uplink acknowledgment)
- PULL_DATA (0x02): Gateway -> Server (keepalive/downlink poll)
- PULL_RESP (0x03): Server -> Gateway (downlink data)
- PULL_ACK  (0x04): Server -> Gateway (pull acknowledgment)
- TX_ACK    (0x05): Gateway -> Server (downlink transmission acknowledgment)

Packet Format:
+----------+----------+----------+----------+----------+----------+
| Version  |  Token   |  Token   |  Type    | Gateway  |  JSON    |
|  (1B)    |  (1B)    |  (1B)    |  (1B)    | EUI (8B) | Payload  |
+----------+----------+----------+----------+----------+----------+
"""

import json
import struct
import time
import random
import asyncio
import socket
import errno
import select
from dataclasses import dataclass, field, asdict
from typing import Optional, List, Callable, Any, Dict
from enum import IntEnum
from datetime import datetime


# Protocol version
PROTOCOL_VERSION = 2


class PacketType(IntEnum):
    """Semtech UDP Protocol packet types"""
    PUSH_DATA = 0x00
    PUSH_ACK = 0x01
    PULL_DATA = 0x02
    PULL_RESP = 0x03
    PULL_ACK = 0x04
    TX_ACK = 0x05


@dataclass
class RxPacket:
    """
    Received packet metadata (uplink).

    Maps to the 'rxpk' JSON object in PUSH_DATA.

    Reference: Semtech PROTOCOL.TXT, Section 4
    """
    # Timestamp
    tmst: int = 0                   # Internal timestamp (microseconds)
    time: Optional[str] = None      # GPS time (ISO 8601)
    tmms: Optional[int] = None      # GPS time (milliseconds since GPS epoch)

    # RF parameters
    freq: float = 868.1             # Frequency in MHz
    chan: int = 0                   # Concentrator IF channel
    rfch: int = 0                   # Concentrator RF chain
    stat: int = 1                   # CRC status: 1=OK, -1=fail, 0=no CRC

    # Modulation
    modu: str = "LORA"              # "LORA" or "FSK"
    datr: str = "SF7BW125"          # Data rate (e.g., "SF7BW125")
    codr: str = "4/5"               # Coding rate (e.g., "4/5")

    # Signal quality
    rssi: int = -50                 # RSSI in dBm
    lsnr: float = 10.0              # SNR in dB

    # Payload
    size: int = 0                   # Payload size
    data: str = ""                  # Base64 encoded PHY payload

    def to_dict(self) -> Dict[str, Any]:
        """Convert to JSON-serializable dictionary"""
        result = {}
        for key, value in asdict(self).items():
            if value is not None:
                result[key] = value
        return result


@dataclass
class TxPacket:
    """
    Transmit packet metadata (downlink).

    Maps to the 'txpk' JSON object in PULL_RESP.

    Reference: Semtech PROTOCOL.TXT, Section 6
    """
    # Timing
    imme: bool = False              # Send immediately
    tmst: Optional[int] = None      # Timestamp to transmit (microseconds)
    tmms: Optional[int] = None      # GPS time to transmit
    time: Optional[str] = None      # GPS time (ISO 8601)

    # RF parameters
    freq: float = 869.525           # Frequency in MHz
    rfch: int = 0                   # Concentrator RF chain
    powe: int = 14                  # TX power in dBm

    # Modulation
    modu: str = "LORA"              # "LORA" or "FSK"
    datr: str = "SF12BW125"         # Data rate
    codr: str = "4/5"               # Coding rate

    # LoRa specific
    ipol: bool = True               # Invert polarity (true for downlink)
    prea: int = 8                   # Preamble length

    # Payload
    size: int = 0                   # Payload size
    data: str = ""                  # Base64 encoded PHY payload
    ncrc: bool = False              # No CRC

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'TxPacket':
        """Create TxPacket from dictionary"""
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


@dataclass
class GatewayStats:
    """Gateway statistics for status message"""
    time: str = ""                  # Current time (ISO 8601)
    lati: float = 0.0               # Latitude
    long: float = 0.0               # Longitude
    alti: int = 0                   # Altitude
    rxnb: int = 0                   # Number of radio packets received
    rxok: int = 0                   # Number of packets with valid CRC
    rxfw: int = 0                   # Number of packets forwarded
    ackr: float = 100.0             # ACK ratio percentage
    dwnb: int = 0                   # Number of downlinks received
    txnb: int = 0                   # Number of packets transmitted


def generate_token() -> bytes:
    """Generate a random 2-byte token for packet tracking"""
    return random.randint(0, 65535).to_bytes(2, 'little')


def build_push_data(gateway_eui: bytes, rxpk_list: List[RxPacket], stats: Optional[GatewayStats] = None) -> bytes:
    """
    Build a PUSH_DATA packet.

    Format: Version(1) | Token(2) | Type(1) | GatewayEUI(8) | JSON

    Args:
        gateway_eui: 8-byte gateway EUI
        rxpk_list: List of received packets
        stats: Optional gateway statistics

    Returns:
        Complete PUSH_DATA packet bytes
    """
    token = generate_token()

    # Build header
    header = struct.pack(
        '<BBB',
        PROTOCOL_VERSION,
        token[0], token[1],
    ) + struct.pack('B', PacketType.PUSH_DATA) + gateway_eui

    # Build JSON payload
    payload = {}
    if rxpk_list:
        payload['rxpk'] = [pkt.to_dict() for pkt in rxpk_list]
    if stats:
        payload['stat'] = asdict(stats)

    json_data = json.dumps(payload).encode('utf-8')

    return header + json_data, token


def build_pull_data(gateway_eui: bytes) -> bytes:
    """
    Build a PULL_DATA packet.

    Format: Version(1) | Token(2) | Type(1) | GatewayEUI(8)

    Args:
        gateway_eui: 8-byte gateway EUI

    Returns:
        Complete PULL_DATA packet bytes and token
    """
    token = generate_token()

    packet = struct.pack(
        '<BBB',
        PROTOCOL_VERSION,
        token[0], token[1],
    ) + struct.pack('B', PacketType.PULL_DATA) + gateway_eui

    return packet, token


def build_tx_ack(token: bytes, gateway_eui: bytes, error: Optional[str] = None) -> bytes:
    """
    Build a TX_ACK packet.

    Format: Version(1) | Token(2) | Type(1) | [JSON]

    Args:
        token: 2-byte token from PULL_RESP
        gateway_eui: 8-byte gateway EUI
        error: Optional error message

    Returns:
        Complete TX_ACK packet bytes
    """
    header = struct.pack(
        '<BBB',
        PROTOCOL_VERSION,
        token[0], token[1],
    ) + struct.pack('B', PacketType.TX_ACK)

    if error:
        payload = json.dumps({'txpk_ack': {'error': error}}).encode('utf-8')
        return header + payload

    return header


def parse_packet(data: bytes) -> Dict[str, Any]:
    """
    Parse a received UDP packet.

    Args:
        data: Raw UDP packet bytes

    Returns:
        Dictionary with parsed packet info:
        - version: Protocol version
        - token: 2-byte token
        - type: PacketType
        - gateway_eui: Gateway EUI (for PUSH_DATA, PULL_DATA)
        - payload: Parsed JSON payload (for PUSH_DATA, PULL_RESP, TX_ACK)
    """
    if len(data) < 4:
        raise ValueError("Packet too short")

    version = data[0]
    token = data[1:3]
    pkt_type = PacketType(data[3])

    result = {
        'version': version,
        'token': token,
        'type': pkt_type,
    }

    if pkt_type == PacketType.PUSH_ACK:
        # PUSH_ACK: Version(1) | Token(2) | Type(1)
        pass

    elif pkt_type == PacketType.PULL_ACK:
        # PULL_ACK: Version(1) | Token(2) | Type(1)
        pass

    elif pkt_type == PacketType.PULL_RESP:
        # PULL_RESP: Version(1) | Token(2) | Type(1) | JSON
        if len(data) > 4:
            result['payload'] = json.loads(data[4:].decode('utf-8'))
            if 'txpk' in result['payload']:
                result['txpk'] = TxPacket.from_dict(result['payload']['txpk'])

    elif pkt_type == PacketType.TX_ACK:
        # TX_ACK: Version(1) | Token(2) | Type(1) | [JSON]
        if len(data) > 4:
            result['payload'] = json.loads(data[4:].decode('utf-8'))

    return result


class PacketForwarder:
    """
    UDP Packet Forwarder client.

    Manages communication with a LoRaWAN Network Server using the
    Semtech UDP Packet Forwarder protocol.
    """

    def __init__(
        self,
        gateway_eui: bytes,
        server_host: str,
        server_port: int = 1700,
        pull_interval: float = 30.0,
        stats_interval: float = 30.0,
    ):
        """
        Initialize PacketForwarder.

        Args:
            gateway_eui: 8-byte gateway EUI
            server_host: Network Server hostname
            server_port: Network Server UDP port (default 1700)
            pull_interval: Interval for PULL_DATA keepalives (seconds)
            stats_interval: Interval for status messages (seconds)
        """
        if len(gateway_eui) != 8:
            raise ValueError("Gateway EUI must be 8 bytes")

        self.gateway_eui = gateway_eui
        self.server_host = server_host
        self.server_port = server_port
        self.pull_interval = pull_interval
        self.stats_interval = stats_interval

        # Socket
        self._socket: Optional[socket.socket] = None
        self._running = False

        # Callbacks
        self.on_downlink: Optional[Callable[[TxPacket], None]] = None
        self.on_push_ack: Optional[Callable[[bytes], None]] = None
        self.on_pull_ack: Optional[Callable[[bytes], None]] = None

        # Statistics
        self.stats = GatewayStats()
        self._pending_tokens: Dict[bytes, float] = {}  # token -> timestamp
        self._ack_count = 0
        self._total_sent = 0

        # Background tasks
        self._pull_task: Optional[asyncio.Task] = None
        self._recv_task: Optional[asyncio.Task] = None

    async def start(self):
        """Start the packet forwarder (open socket, start background tasks)"""
        if self._running:
            return

        # Create UDP socket
        self._socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._socket.setblocking(False)

        self._running = True

        # Start background tasks
        self._pull_task = asyncio.create_task(self._pull_data_loop())
        self._recv_task = asyncio.create_task(self._receive_loop())

    async def stop(self):
        """Stop the packet forwarder"""
        self._running = False

        # Cancel background tasks
        if self._pull_task:
            self._pull_task.cancel()
            try:
                await self._pull_task
            except asyncio.CancelledError:
                pass

        if self._recv_task:
            self._recv_task.cancel()
            try:
                await self._recv_task
            except asyncio.CancelledError:
                pass

        # Close socket
        if self._socket:
            self._socket.close()
            self._socket = None

    async def send_uplink(self, rxpk: RxPacket) -> bytes:
        """
        Send an uplink packet to the server.

        Args:
            rxpk: Received packet metadata

        Returns:
            Token used for this packet
        """
        return await self.send_uplinks([rxpk])

    async def send_uplinks(self, rxpk_list: List[RxPacket]) -> bytes:
        """
        Send multiple uplink packets to the server.

        Args:
            rxpk_list: List of received packet metadata

        Returns:
            Token used for this packet
        """
        packet, token = build_push_data(self.gateway_eui, rxpk_list)

        self._pending_tokens[bytes(token)] = time.time()
        self._total_sent += 1
        self.stats.rxnb += len(rxpk_list)
        self.stats.rxok += len(rxpk_list)
        self.stats.rxfw += len(rxpk_list)

        await self._send(packet)
        return token

    async def send_status(self):
        """Send gateway status message"""
        self.stats.time = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S GMT')

        # Calculate ACK ratio
        if self._total_sent > 0:
            self.stats.ackr = (self._ack_count / self._total_sent) * 100

        packet, token = build_push_data(self.gateway_eui, [], self.stats)
        await self._send(packet)

    async def _send(self, data: bytes):
        """Send raw data to server"""
        if not self._socket or not self._running:
            return

        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            self._socket.sendto,
            data,
            (self.server_host, self.server_port)
        )

    async def _pull_data_loop(self):
        """Background task: send PULL_DATA keepalives"""
        while self._running:
            try:
                packet, token = build_pull_data(self.gateway_eui)
                self._pending_tokens[bytes(token)] = time.time()
                await self._send(packet)
                await asyncio.sleep(self.pull_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"Error in pull_data_loop: {e}")
                await asyncio.sleep(1)

    async def _receive_loop(self):
        """Background task: receive and process server responses"""
        while self._running:
            try:
                # Use select to wait for data with timeout (prevents EAGAIN spam)
                readable, _, _ = select.select([self._socket], [], [], 0.1)
                if not readable:
                    await asyncio.sleep(0.01)  # Small yield to event loop
                    continue

                try:
                    data, addr = self._socket.recvfrom(65535)
                except BlockingIOError:
                    # No data available, this is normal for non-blocking sockets
                    continue
                except socket.error as e:
                    if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                        # No data available, continue
                        continue
                    elif self._running:
                        # Real error, only log if still running
                        print(f"Socket error in receive loop: {e}")
                    continue

                if not data:
                    continue

                # Parse packet
                try:
                    parsed = parse_packet(data)
                except Exception as e:
                    print(f"Failed to parse packet: {e}")
                    continue

                # Handle based on type
                pkt_type = parsed['type']
                token = parsed['token']

                if pkt_type == PacketType.PUSH_ACK:
                    self._ack_count += 1
                    if bytes(token) in self._pending_tokens:
                        del self._pending_tokens[bytes(token)]
                    if self.on_push_ack:
                        self.on_push_ack(token)

                elif pkt_type == PacketType.PULL_ACK:
                    if bytes(token) in self._pending_tokens:
                        del self._pending_tokens[bytes(token)]
                    if self.on_pull_ack:
                        self.on_pull_ack(token)

                elif pkt_type == PacketType.PULL_RESP:
                    self.stats.dwnb += 1
                    if 'txpk' in parsed and self.on_downlink:
                        self.on_downlink(parsed['txpk'])

                    # Send TX_ACK
                    tx_ack = build_tx_ack(token, self.gateway_eui)
                    await self._send(tx_ack)
                    self.stats.txnb += 1

            except asyncio.CancelledError:
                break
            except Exception as e:
                if self._running:
                    print(f"Error in receive_loop: {e}")
                await asyncio.sleep(0.1)

    @property
    def is_connected(self) -> bool:
        """Check if the forwarder is running and has received ACKs recently"""
        return self._running and self._ack_count > 0

    def set_location(self, latitude: float, longitude: float, altitude: int = 0):
        """Set gateway location for status messages"""
        self.stats.lati = latitude
        self.stats.long = longitude
        self.stats.alti = altitude


def eui_to_bytes(eui_str: str) -> bytes:
    """Convert EUI string to bytes (e.g., 'AA555A0000000001' -> bytes)"""
    eui_str = eui_str.replace(':', '').replace('-', '').upper()
    return bytes.fromhex(eui_str)


def bytes_to_eui(eui_bytes: bytes) -> str:
    """Convert EUI bytes to string"""
    return eui_bytes.hex().upper()
