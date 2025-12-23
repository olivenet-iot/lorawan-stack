"""
LoRaWAN Simulator Library

This package provides tools for simulating LoRaWAN devices and gateways
for testing The Things Stack without real hardware.

Modules:
    lorawan_crypto: LoRaWAN cryptographic operations (MIC, encryption, key derivation)
    packet_forwarder: Semtech UDP Packet Forwarder protocol implementation
    device: Virtual LoRaWAN end device simulation
    gateway: Virtual LoRaWAN gateway simulation
"""

from .lorawan_crypto import (
    compute_mic,
    compute_join_request_mic,
    compute_uplink_mic,
    encrypt_frm_payload,
    decrypt_join_accept,
    derive_session_keys,
)

from .packet_forwarder import (
    PacketForwarder,
    PacketType,
    RxPacket,
    TxPacket,
)

from .device import VirtualDevice

from .gateway import VirtualGateway

__version__ = "1.0.0"
__all__ = [
    # Crypto
    "compute_mic",
    "compute_join_request_mic",
    "compute_uplink_mic",
    "encrypt_frm_payload",
    "decrypt_join_accept",
    "derive_session_keys",
    # Packet Forwarder
    "PacketForwarder",
    "PacketType",
    "RxPacket",
    "TxPacket",
    # Device & Gateway
    "VirtualDevice",
    "VirtualGateway",
]
