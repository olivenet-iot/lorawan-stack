"""
Virtual LoRaWAN Gateway

Simulates a LoRaWAN gateway using UDP Packet Forwarder protocol.
Can forward uplinks from virtual devices and receive downlinks.

Features:
- Semtech UDP Packet Forwarder protocol
- Multiple device support
- Automatic PULL_DATA keepalives
- Downlink reception and callback
- Gateway statistics
"""

import asyncio
import base64
import time
import random
from dataclasses import dataclass, field
from typing import Optional, Callable, List, Dict, Any
from datetime import datetime

from .packet_forwarder import (
    PacketForwarder,
    RxPacket,
    TxPacket,
    eui_to_bytes,
    bytes_to_eui,
)


# EU868 default frequencies
EU868_UPLINK_FREQUENCIES = [
    868.1,  # Channel 0
    868.3,  # Channel 1
    868.5,  # Channel 2
]

# Data rate strings (EU868)
DATA_RATES = {
    0: "SF12BW125",
    1: "SF11BW125",
    2: "SF10BW125",
    3: "SF9BW125",
    4: "SF8BW125",
    5: "SF7BW125",
    6: "SF7BW250",
    7: "FSK",
}


@dataclass
class RadioParams:
    """Radio parameters for uplink simulation"""
    frequency: float = 868.1      # MHz
    data_rate: int = 5            # DR index (SF7BW125)
    coding_rate: str = "4/5"
    tx_power: int = 14            # dBm
    rssi: int = -50               # dBm
    snr: float = 10.0             # dB


@dataclass
class GatewayLocation:
    """Gateway location information"""
    latitude: float = 0.0
    longitude: float = 0.0
    altitude: int = 0


@dataclass
class GatewayConfig:
    """Gateway configuration"""
    eui: str = "AA555A0000000001"
    server_host: str = "localhost"
    server_port: int = 1700
    frequency_plan: str = "EU_863_870"
    location: GatewayLocation = field(default_factory=GatewayLocation)
    pull_interval: float = 30.0
    status_interval: float = 30.0


class VirtualGateway:
    """
    Virtual LoRaWAN Gateway.

    Simulates a LoRaWAN gateway connecting to a Network Server
    using the Semtech UDP Packet Forwarder protocol.
    """

    def __init__(
        self,
        config: Optional[GatewayConfig] = None,
        eui: Optional[str] = None,
        server_host: str = "localhost",
        server_port: int = 1700,
    ):
        """
        Initialize a virtual gateway.

        Args:
            config: Full gateway configuration
            eui: Gateway EUI (alternative to config)
            server_host: Network Server hostname
            server_port: Network Server UDP port
        """
        if config:
            self.config = config
        else:
            self.config = GatewayConfig(
                eui=eui or "AA555A0000000001",
                server_host=server_host,
                server_port=server_port,
            )

        # Parse EUI
        self.eui = eui_to_bytes(self.config.eui)

        # Create packet forwarder
        self.packet_forwarder = PacketForwarder(
            gateway_eui=self.eui,
            server_host=self.config.server_host,
            server_port=self.config.server_port,
            pull_interval=self.config.pull_interval,
        )

        # Set location
        self.packet_forwarder.set_location(
            self.config.location.latitude,
            self.config.location.longitude,
            self.config.location.altitude,
        )

        # Callbacks
        self.on_downlink: Optional[Callable[[TxPacket], None]] = None
        self.on_connected: Optional[Callable[[], None]] = None
        self.on_disconnected: Optional[Callable[[], None]] = None

        # State
        self._connected = False
        self._ack_received = False

        # Internal timestamp counter (microseconds, wraps at 2^32)
        self._tmst_counter = random.randint(0, 2**32 - 1)

        # Statistics
        self.stats = {
            'uplinks_sent': 0,
            'uplinks_acked': 0,
            'downlinks_received': 0,
            'pull_acks': 0,
            'connected_at': None,
        }

    async def connect(self) -> bool:
        """
        Connect to the Network Server.

        Starts the packet forwarder and waits for initial PULL_ACK.

        Returns:
            True if connection successful
        """
        # Set up callbacks
        self.packet_forwarder.on_push_ack = self._on_push_ack
        self.packet_forwarder.on_pull_ack = self._on_pull_ack
        self.packet_forwarder.on_downlink = self._on_downlink

        # Start packet forwarder
        await self.packet_forwarder.start()

        # Wait for first PULL_ACK (with timeout)
        self._ack_received = False
        for _ in range(10):  # 10 second timeout
            await asyncio.sleep(1)
            if self._ack_received:
                self._connected = True
                self.stats['connected_at'] = datetime.utcnow().isoformat()
                if self.on_connected:
                    self.on_connected()
                return True

        return False

    async def disconnect(self):
        """Disconnect from the Network Server"""
        await self.packet_forwarder.stop()
        self._connected = False
        if self.on_disconnected:
            self.on_disconnected()

    @property
    def is_connected(self) -> bool:
        """Check if gateway is connected"""
        return self._connected and self.packet_forwarder.is_connected

    async def send_uplink(
        self,
        phy_payload: bytes,
        radio_params: Optional[RadioParams] = None,
    ) -> bool:
        """
        Send an uplink packet to the Network Server.

        Args:
            phy_payload: Complete PHY payload (MHDR|...|MIC)
            radio_params: Optional radio parameters

        Returns:
            True if packet was sent successfully
        """
        if not self._connected:
            return False

        params = radio_params or RadioParams()

        # Update internal timestamp
        self._tmst_counter = (self._tmst_counter + random.randint(100000, 1000000)) % (2**32)

        # Build RxPacket
        rxpk = RxPacket(
            tmst=self._tmst_counter,
            time=datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%fZ'),
            freq=params.frequency,
            chan=0,
            rfch=0,
            stat=1,  # CRC OK
            modu="LORA",
            datr=DATA_RATES.get(params.data_rate, "SF7BW125"),
            codr=params.coding_rate,
            rssi=params.rssi,
            lsnr=params.snr,
            size=len(phy_payload),
            data=base64.b64encode(phy_payload).decode('ascii'),
        )

        await self.packet_forwarder.send_uplink(rxpk)
        self.stats['uplinks_sent'] += 1

        return True

    async def send_uplink_base64(
        self,
        data_base64: str,
        radio_params: Optional[RadioParams] = None,
    ) -> bool:
        """
        Send an uplink with base64-encoded payload.

        Args:
            data_base64: Base64-encoded PHY payload
            radio_params: Optional radio parameters

        Returns:
            True if sent successfully
        """
        phy_payload = base64.b64decode(data_base64)
        return await self.send_uplink(phy_payload, radio_params)

    async def send_status(self):
        """Send gateway status message"""
        await self.packet_forwarder.send_status()

    def simulate_radio_params(
        self,
        data_rate: int = 5,
        rssi_min: int = -120,
        rssi_max: int = -30,
        snr_min: float = -20.0,
        snr_max: float = 15.0,
    ) -> RadioParams:
        """
        Generate simulated radio parameters.

        Args:
            data_rate: Data rate index
            rssi_min: Minimum RSSI value
            rssi_max: Maximum RSSI value
            snr_min: Minimum SNR value
            snr_max: Maximum SNR value

        Returns:
            RadioParams with random values
        """
        return RadioParams(
            frequency=random.choice(EU868_UPLINK_FREQUENCIES),
            data_rate=data_rate,
            coding_rate="4/5",
            rssi=random.randint(rssi_min, rssi_max),
            snr=round(random.uniform(snr_min, snr_max), 1),
        )

    def _on_push_ack(self, token: bytes):
        """Handle PUSH_ACK from server"""
        self.stats['uplinks_acked'] += 1

    def _on_pull_ack(self, token: bytes):
        """Handle PULL_ACK from server"""
        self._ack_received = True
        self.stats['pull_acks'] += 1

    def _on_downlink(self, txpk: TxPacket):
        """Handle downlink from server"""
        self.stats['downlinks_received'] += 1
        if self.on_downlink:
            self.on_downlink(txpk)

    def get_stats(self) -> Dict[str, Any]:
        """Get gateway statistics"""
        return {
            **self.stats,
            'eui': bytes_to_eui(self.eui),
            'connected': self.is_connected,
        }


class MultiGateway:
    """
    Manager for multiple virtual gateways.

    Useful for simulating multi-gateway scenarios.
    """

    def __init__(self):
        self.gateways: Dict[str, VirtualGateway] = {}

    def add_gateway(self, gateway: VirtualGateway) -> str:
        """Add a gateway to the manager"""
        eui = bytes_to_eui(gateway.eui)
        self.gateways[eui] = gateway
        return eui

    def remove_gateway(self, eui: str):
        """Remove a gateway from the manager"""
        if eui in self.gateways:
            del self.gateways[eui]

    async def connect_all(self) -> Dict[str, bool]:
        """Connect all gateways"""
        results = {}
        tasks = []

        for eui, gw in self.gateways.items():
            tasks.append((eui, gw.connect()))

        for eui, task in tasks:
            results[eui] = await task

        return results

    async def disconnect_all(self):
        """Disconnect all gateways"""
        for gw in self.gateways.values():
            await gw.disconnect()

    async def send_uplink_to_all(
        self,
        phy_payload: bytes,
        radio_params: Optional[RadioParams] = None,
        delay_between: float = 0.0,
    ):
        """
        Send an uplink through all gateways.

        Simulates the same packet being received by multiple gateways.

        Args:
            phy_payload: PHY payload to send
            radio_params: Optional radio parameters (will vary per gateway)
            delay_between: Delay between gateway transmissions
        """
        for gw in self.gateways.values():
            params = radio_params or gw.simulate_radio_params()
            await gw.send_uplink(phy_payload, params)
            if delay_between > 0:
                await asyncio.sleep(delay_between)

    def get_all_stats(self) -> Dict[str, Dict[str, Any]]:
        """Get statistics from all gateways"""
        return {eui: gw.get_stats() for eui, gw in self.gateways.items()}


def create_gateway_from_config(config: Dict[str, Any]) -> VirtualGateway:
    """Create a VirtualGateway from configuration dictionary"""
    location = GatewayLocation()
    if 'location' in config:
        loc = config['location']
        location = GatewayLocation(
            latitude=loc.get('latitude', 0.0),
            longitude=loc.get('longitude', 0.0),
            altitude=loc.get('altitude', 0),
        )

    gw_config = GatewayConfig(
        eui=config.get('eui', 'AA555A0000000001'),
        server_host=config.get('server_host', config.get('host', 'localhost')),
        server_port=config.get('server_port', config.get('port', 1700)),
        frequency_plan=config.get('frequency_plan', 'EU_863_870'),
        location=location,
        pull_interval=config.get('pull_interval', 30.0),
        status_interval=config.get('status_interval', 30.0),
    )

    return VirtualGateway(config=gw_config)
