#!/usr/bin/env python3
"""
Join Tester

Dedicated tool for testing OTAA join flow with detailed diagnostics.

Usage:
    python join_tester.py --dev-eui 70B3D57ED0000001 --app-key 00112233...
    python join_tester.py --config config.yml

Features:
    - Step-by-step join flow visualization
    - MIC calculation verification
    - Timing analysis
    - Detailed error diagnosis
"""

import argparse
import asyncio
import base64
import struct
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

import yaml
from colorama import init, Fore, Style

# Initialize colorama
init()

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent))

from lib.device import VirtualDevice, eui_from_string, key_from_string
from lib.gateway import VirtualGateway, GatewayConfig, GatewayLocation
from lib.packet_forwarder import TxPacket
from lib.lorawan_crypto import (
    compute_join_request_mic,
    decrypt_join_accept,
    verify_join_accept_mic,
    derive_session_keys,
    parse_mhdr,
)


class JoinTester:
    """OTAA Join flow tester with detailed diagnostics"""

    def __init__(self, config: dict):
        self.config = config
        self.gateway: Optional[VirtualGateway] = None
        self.join_accept_received = asyncio.Event()
        self.join_accept_payload: Optional[bytes] = None
        self.timings: dict = {}

    def log(self, message: str, indent: int = 0, symbol: str = ""):
        """Log with formatting"""
        prefix = "  " * indent
        if symbol:
            print(f"{prefix}{symbol} {message}")
        else:
            print(f"{prefix}{message}")

    def log_section(self, title: str):
        """Log a section header"""
        print()
        print(f"{Fore.CYAN}{Style.BRIGHT}{title}{Style.RESET_ALL}")

    def log_success(self, message: str, indent: int = 0):
        """Log success message"""
        self.log(message, indent, f"{Fore.GREEN}✓{Style.RESET_ALL}")

    def log_error(self, message: str, indent: int = 0):
        """Log error message"""
        self.log(message, indent, f"{Fore.RED}✗{Style.RESET_ALL}")

    def log_info(self, message: str, indent: int = 0):
        """Log info message"""
        self.log(message, indent, f"{Fore.BLUE}├──{Style.RESET_ALL}")

    def log_last(self, message: str, indent: int = 0):
        """Log last item in a list"""
        self.log(message, indent, f"{Fore.BLUE}└──{Style.RESET_ALL}")

    def _on_downlink(self, txpk: TxPacket):
        """Handle downlink"""
        try:
            payload = base64.b64decode(txpk.data)
            mhdr = payload[0]
            mtype = (mhdr >> 5) & 0x07

            if mtype == 1:  # Join Accept
                self.join_accept_payload = payload
                self.timings['join_accept_received'] = time.time()
                self.join_accept_received.set()
        except Exception as e:
            self.log_error(f"Error processing downlink: {e}")

    async def run(
        self,
        dev_eui: str,
        join_eui: str,
        app_key: str,
        timeout: float = 10.0
    ) -> bool:
        """
        Run the join test.

        Args:
            dev_eui: Device EUI
            join_eui: Join EUI
            app_key: Application Key
            timeout: Join timeout in seconds

        Returns:
            True if join successful
        """
        print()
        print(f"{Fore.YELLOW}{Style.BRIGHT}OTAA Join Test - DevEUI: {dev_eui}{Style.RESET_ALL}")
        print("=" * 60)

        # Create device
        device = VirtualDevice(
            dev_eui=eui_from_string(dev_eui),
            join_eui=eui_from_string(join_eui),
            app_key=key_from_string(app_key),
        )

        # Setup gateway
        gw_config = self.config.get('gateway', {})
        stack_config = self.config.get('stack', {})

        location = GatewayLocation(
            latitude=gw_config.get('location', {}).get('latitude', 0),
            longitude=gw_config.get('location', {}).get('longitude', 0),
            altitude=gw_config.get('location', {}).get('altitude', 0),
        )

        config = GatewayConfig(
            eui=gw_config.get('eui', 'AA555A0000000001'),
            server_host=stack_config.get('host', 'localhost'),
            server_port=stack_config.get('gateway_udp_port', 1700),
            location=location,
        )

        self.gateway = VirtualGateway(config=config)
        self.gateway.on_downlink = self._on_downlink

        # Step 1: Prepare Join Request
        self.log_section("Step 1: Preparing Join Request")

        join_request = device.build_join_request()
        dev_nonce = device._last_dev_nonce

        # Compute MIC for display
        mhdr = join_request[0]
        mic = join_request[-4:]

        self.log_info(f"DevEUI: {dev_eui}")
        self.log_info(f"JoinEUI: {join_eui}")
        self.log_info(f"DevNonce: 0x{dev_nonce:04X}")
        self.log_info(f"MIC: 0x{mic.hex().upper()}")
        self.log_last(f"PHY Payload: {join_request.hex().upper()}")

        # Step 2: Connect and send
        self.log_section("Step 2: Sending via Gateway " + config.eui)

        connected = await self.gateway.connect()
        if not connected:
            self.log_error("Failed to connect gateway")
            return False

        self.log_success("Gateway connected")

        self.timings['join_request_sent'] = time.time()

        radio = self.gateway.simulate_radio_params()
        self.log_info(f"Frequency: {radio.frequency} MHz")
        self.log_info(f"Data Rate: SF7BW125")
        self.log_last(f"Timestamp: {datetime.utcnow().isoformat()}Z")

        await self.gateway.send_uplink(join_request, radio)
        self.log_success("Join Request sent")

        # Step 3: Wait for Join Accept
        self.log_section("Step 3: Waiting for Join Accept...")

        self.log_info(f"RX1 Window (5s): ⏳ Waiting...")

        try:
            await asyncio.wait_for(self.join_accept_received.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            self.log_error(f"Timeout after {timeout}s - No Join Accept received")
            await self.gateway.disconnect()
            return False

        response_time = self.timings['join_accept_received'] - self.timings['join_request_sent']
        self.log_success(f"Received!")
        self.log_last(f"Response time: {response_time:.2f}s")

        # Step 4: Process Join Accept
        self.log_section("Step 4: Processing Join Accept")

        ja_payload = self.join_accept_payload
        self.log_info(f"Encrypted: {ja_payload.hex().upper()[:40]}...")

        try:
            # Decrypt
            mhdr = ja_payload[0]
            encrypted = ja_payload[1:]
            decrypted = decrypt_join_accept(device.app_key, encrypted)

            self.log_success("Decrypted successfully")

            # Parse
            join_nonce = decrypted[0:3]
            net_id = decrypted[3:6]
            dev_addr = decrypted[6:10]
            dl_settings = decrypted[10]
            rx_delay = decrypted[11]
            received_mic = decrypted[-4:]

            self.log_info(f"JoinNonce: 0x{join_nonce.hex().upper()}")
            self.log_info(f"NetID: 0x{net_id.hex().upper()}")
            self.log_info(f"DevAddr: {dev_addr.hex().upper()}")
            self.log_info(f"DLSettings: 0x{dl_settings:02X}")
            self.log_info(f"RxDelay: {rx_delay}")

            # Verify MIC
            if verify_join_accept_mic(device.app_key, mhdr, decrypted):
                self.log_success("MIC Valid")
            else:
                self.log_error("MIC Invalid!")
                await self.gateway.disconnect()
                return False

        except Exception as e:
            self.log_error(f"Decryption failed: {e}")
            await self.gateway.disconnect()
            return False

        # Step 5: Derive Session Keys
        self.log_section("Step 5: Deriving Session Keys")

        try:
            nwk_s_key, app_s_key = derive_session_keys(
                device.app_key,
                join_nonce,
                net_id,
                dev_nonce
            )

            self.log_info(f"NwkSKey: {nwk_s_key.hex().upper()}")
            self.log_last(f"AppSKey: {app_s_key.hex().upper()}")

            self.log_success("Session keys derived successfully")

        except Exception as e:
            self.log_error(f"Key derivation failed: {e}")
            await self.gateway.disconnect()
            return False

        # Final result
        print()
        print(f"{Fore.GREEN}{Style.BRIGHT}✓ JOIN SUCCESSFUL{Style.RESET_ALL}")
        print()
        print("Device is now activated and ready to send uplinks.")
        print(f"  DevAddr: {dev_addr.hex().upper()}")
        print(f"  Total time: {response_time:.2f}s")
        print()

        await self.gateway.disconnect()
        return True


def load_config(config_path: str) -> dict:
    """Load configuration from YAML file"""
    path = Path(config_path)
    if path.exists():
        with open(path, 'r') as f:
            return yaml.safe_load(f)
    return {}


def main():
    parser = argparse.ArgumentParser(
        description="LoRaWAN OTAA Join Tester",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument('--config', '-c', default='config.yml',
                        help='Configuration file')
    parser.add_argument('--dev-eui', required=True,
                        help='Device EUI')
    parser.add_argument('--join-eui', default='0000000000000000',
                        help='Join EUI (AppEUI)')
    parser.add_argument('--app-key', required=True,
                        help='Application Key')
    parser.add_argument('--timeout', '-t', type=float, default=10,
                        help='Join timeout (seconds)')

    args = parser.parse_args()

    # Load config
    config = load_config(args.config)

    # Create and run tester
    tester = JoinTester(config)
    success = asyncio.run(tester.run(
        dev_eui=args.dev_eui,
        join_eui=args.join_eui,
        app_key=args.app_key,
        timeout=args.timeout,
    ))

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
