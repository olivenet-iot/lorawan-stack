#!/usr/bin/env python3
"""
Device Simulator

Simulates LoRaWAN end devices performing OTAA join and sending uplinks.

Usage:
    python device_simulator.py --scenario scenarios/single_device.yml
    python device_simulator.py --dev-eui 70B3D57ED0000001 --app-key 00112233...
    python device_simulator.py --abp --dev-addr 260BXXXX

Examples:
    # Run a scenario file
    python device_simulator.py --scenario scenarios/single_device.yml

    # Single device OTAA join and uplinks
    python device_simulator.py --dev-eui 70B3D57ED0000001 \\
        --join-eui 0000000000000000 \\
        --app-key 00112233445566778899AABBCCDDEEFF \\
        --uplinks 5

    # ABP device (pre-activated)
    python device_simulator.py --abp \\
        --dev-addr 260B1234 \\
        --nwk-s-key 00112233445566778899AABBCCDDEEFF \\
        --app-s-key FFEEDDCCBBAA00998877665544332211

Features:
    - OTAA join flow
    - ABP activation
    - Periodic uplink sending
    - Downlink processing
    - Scenario-based batch testing
    - Result logging (JSON)
"""

import argparse
import asyncio
import base64
import json
import os
import sys
import signal
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List

import yaml
from colorama import init, Fore, Style

# Initialize colorama
init()

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent))

from lib.device import VirtualDevice, eui_from_string, key_from_string
from lib.gateway import VirtualGateway, GatewayConfig, GatewayLocation, RadioParams
from lib.packet_forwarder import TxPacket


class DeviceSimulator:
    """Device simulator for OTAA/ABP testing"""

    def __init__(self, config: dict):
        self.config = config
        self.gateway: Optional[VirtualGateway] = None
        self.devices: Dict[str, VirtualDevice] = {}
        self.running = False
        self.results: List[Dict[str, Any]] = []

        # Pending join accepts (dev_eui -> event)
        self._pending_joins: Dict[str, asyncio.Event] = {}
        self._join_accepts: Dict[str, bytes] = {}

    def log(self, message: str, level: str = "INFO"):
        """Log a message with timestamp and color"""
        timestamp = datetime.now().strftime('%H:%M:%S')

        colors = {
            "ERROR": Fore.RED,
            "WARN": Fore.YELLOW,
            "SUCCESS": Fore.GREEN,
            "DEBUG": Fore.CYAN,
            "INFO": Fore.WHITE,
        }
        color = colors.get(level, Fore.WHITE)
        print(f"{Fore.BLUE}[{timestamp}]{Style.RESET_ALL} {color}{message}{Style.RESET_ALL}")

    async def setup_gateway(self) -> bool:
        """Set up virtual gateway for forwarding"""
        gw_config = self.config.get('gateway', {})
        stack_config = self.config.get('stack', {})

        location = GatewayLocation()
        if 'location' in gw_config:
            loc = gw_config['location']
            location = GatewayLocation(
                latitude=loc.get('latitude', 0.0),
                longitude=loc.get('longitude', 0.0),
                altitude=loc.get('altitude', 0),
            )

        config = GatewayConfig(
            eui=gw_config.get('eui', 'AA555A0000000001'),
            server_host=stack_config.get('host', 'localhost'),
            server_port=stack_config.get('gateway_udp_port', 1700),
            location=location,
        )

        self.gateway = VirtualGateway(config=config)
        self.gateway.on_downlink = self._on_downlink

        self.log(f"Connecting gateway {config.eui}...")

        connected = await self.gateway.connect()
        if not connected:
            self.log("Failed to connect gateway", "ERROR")
            return False

        self.log("Gateway connected", "SUCCESS")
        return True

    def _on_downlink(self, txpk: TxPacket):
        """Handle downlink from server"""
        try:
            payload = base64.b64decode(txpk.data)
            mhdr = payload[0]
            mtype = (mhdr >> 5) & 0x07

            # Check if it's a Join Accept (MType = 1)
            if mtype == 1:
                self._handle_join_accept(payload)
            else:
                self._handle_data_downlink(payload)

        except Exception as e:
            self.log(f"Error processing downlink: {e}", "ERROR")

    def _handle_join_accept(self, payload: bytes):
        """Handle Join Accept message"""
        self.log("← Join Accept received")

        # Store the join accept for any pending device
        for dev_eui, event in self._pending_joins.items():
            if not event.is_set():
                self._join_accepts[dev_eui] = payload
                event.set()
                break

    def _handle_data_downlink(self, payload: bytes):
        """Handle data downlink message"""
        # Extract DevAddr from payload (bytes 1-4)
        if len(payload) < 12:
            return

        dev_addr = payload[1:5]

        # Find device with this DevAddr
        for device in self.devices.values():
            if device.session and device.session.dev_addr == dev_addr:
                try:
                    app_payload, info = device.process_downlink(payload)
                    self.log(f"← Downlink for device {device.dev_eui.hex().upper()}")
                    if info.get('ack'):
                        self.log("  ACK received", "SUCCESS")
                    if app_payload:
                        self.log(f"  Payload: {app_payload.hex()}")
                except Exception as e:
                    self.log(f"Error processing downlink: {e}", "ERROR")
                break

    async def join_device(self, device: VirtualDevice, timeout: float = 10.0) -> bool:
        """
        Perform OTAA join for a device.

        Args:
            device: Device to join
            timeout: Join timeout in seconds

        Returns:
            True if join successful
        """
        dev_eui_str = device.dev_eui.hex().upper()
        self.log(f"Device {dev_eui_str} starting OTAA join...")

        # Create pending join event
        event = asyncio.Event()
        self._pending_joins[dev_eui_str] = event

        try:
            # Build and send join request
            join_request = device.build_join_request()
            self.log(f"→ Join Request sent")

            await self.gateway.send_uplink(
                join_request,
                self.gateway.simulate_radio_params()
            )

            # Wait for join accept
            try:
                await asyncio.wait_for(event.wait(), timeout=timeout)
            except asyncio.TimeoutError:
                self.log(f"Join timeout after {timeout}s", "ERROR")
                return False

            # Process join accept
            if dev_eui_str in self._join_accepts:
                join_accept = self._join_accepts[dev_eui_str]
                device.process_join_accept(join_accept)
                self.log(f"✓ Device activated! DevAddr: {device.session.dev_addr.hex().upper()}", "SUCCESS")
                self.log(f"  Session keys derived successfully")
                return True
            else:
                self.log("No join accept received", "ERROR")
                return False

        finally:
            # Cleanup
            del self._pending_joins[dev_eui_str]
            if dev_eui_str in self._join_accepts:
                del self._join_accepts[dev_eui_str]

    async def send_uplinks(
        self,
        device: VirtualDevice,
        count: int,
        interval: float,
        port: int = 1,
        payload_generator: str = "counter",
        confirmed: bool = False
    ):
        """
        Send multiple uplinks from a device.

        Args:
            device: Device to send from
            count: Number of uplinks
            interval: Interval between uplinks (seconds)
            port: FPort
            payload_generator: "counter", "random", or "static"
            confirmed: Use confirmed uplinks
        """
        dev_eui_str = device.dev_eui.hex().upper()

        for i in range(count):
            if not self.running:
                break

            # Generate payload
            if payload_generator == "counter":
                payload = bytes([i & 0xFF, (i >> 8) & 0xFF])
            elif payload_generator == "random":
                payload = os.urandom(10)
            else:
                payload = b'\x01\x02\x03\x04\x05'

            # Build and send uplink
            uplink = device.build_uplink(port, payload, confirmed)
            await self.gateway.send_uplink(
                uplink,
                self.gateway.simulate_radio_params()
            )

            self.log(f"→ Uplink #{i+1} sent (port: {port}, payload: {payload.hex()})")

            # Record result
            self.results.append({
                'timestamp': datetime.utcnow().isoformat(),
                'type': 'uplink',
                'dev_eui': dev_eui_str,
                'fcnt': device.session.fcnt_up - 1,
                'port': port,
                'payload': payload.hex(),
                'confirmed': confirmed,
            })

            if i < count - 1:
                await asyncio.sleep(interval)

    async def run_scenario(self, scenario: dict):
        """Run a test scenario"""
        self.log(f"Running scenario: {scenario.get('name', 'Unnamed')}")

        # Get devices from scenario
        devices_config = scenario.get('devices', [])
        test_config = scenario.get('test', {})

        join_timeout = test_config.get('join_timeout', 10)
        uplink_count = test_config.get('uplink_count', 5)
        uplink_interval = test_config.get('uplink_interval', 10)
        payload_generator = test_config.get('payload_generator', 'counter')

        # Create devices
        for dev_config in devices_config:
            device = VirtualDevice(
                dev_eui=eui_from_string(dev_config['dev_eui']),
                join_eui=eui_from_string(dev_config.get('join_eui', '0000000000000000')),
                app_key=key_from_string(dev_config['app_key']),
            )
            self.devices[dev_config['dev_eui']] = device

        # Join and test each device
        for dev_eui, device in self.devices.items():
            if not self.running:
                break

            # OTAA join
            success = await self.join_device(device, join_timeout)
            if not success:
                self.log(f"Device {dev_eui} failed to join", "ERROR")
                continue

            # Send uplinks
            await self.send_uplinks(
                device,
                count=uplink_count,
                interval=uplink_interval,
                payload_generator=payload_generator,
            )

    async def run(self, args):
        """Main run method"""
        self.running = True

        # Setup gateway
        if not await self.setup_gateway():
            return False

        try:
            if args.scenario:
                # Run from scenario file
                with open(args.scenario, 'r') as f:
                    scenario = yaml.safe_load(f)
                await self.run_scenario(scenario)

            elif args.dev_eui:
                # Single device mode
                device = VirtualDevice(
                    dev_eui=eui_from_string(args.dev_eui),
                    join_eui=eui_from_string(args.join_eui or '0000000000000000'),
                    app_key=key_from_string(args.app_key),
                )
                self.devices[args.dev_eui] = device

                if args.abp:
                    # ABP activation
                    device.activate_abp(
                        dev_addr=bytes.fromhex(args.dev_addr),
                        nwk_s_key=key_from_string(args.nwk_s_key),
                        app_s_key=key_from_string(args.app_s_key),
                    )
                    self.log(f"Device activated (ABP) with DevAddr: {args.dev_addr}")
                else:
                    # OTAA join
                    success = await self.join_device(device, timeout=10)
                    if not success:
                        return False

                # Send uplinks
                await self.send_uplinks(
                    device,
                    count=args.uplinks,
                    interval=args.interval,
                )

            else:
                self.log("No device or scenario specified", "ERROR")
                return False

        finally:
            # Save results
            if self.results and args.output:
                output_path = Path(args.output)
                output_path.parent.mkdir(parents=True, exist_ok=True)
                with open(output_path, 'w') as f:
                    json.dump(self.results, f, indent=2)
                self.log(f"Results saved to {args.output}")

            # Disconnect gateway
            if self.gateway:
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
        description="LoRaWAN Device Simulator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # Config and scenario
    parser.add_argument('--config', '-c', default='config.yml',
                        help='Configuration file')
    parser.add_argument('--server', default='localhost',
                        help='TTS server address')
    parser.add_argument('--port', type=int, default=1700,
                        help='UDP port')
    parser.add_argument('--gateway-eui', default='AA555A0000000001',
                        help='Gateway EUI')
    parser.add_argument('--scenario', '-s',
                        help='Scenario file to run')

    # Device parameters (for single device mode)
    parser.add_argument('--dev-eui', help='Device EUI')
    parser.add_argument('--join-eui', help='Join EUI (AppEUI)')
    parser.add_argument('--app-key', help='Application Key')

    # ABP parameters
    parser.add_argument('--abp', action='store_true',
                        help='Use ABP activation')
    parser.add_argument('--dev-addr', help='Device Address (ABP)')
    parser.add_argument('--nwk-s-key', help='Network Session Key (ABP)')
    parser.add_argument('--app-s-key', help='Application Session Key (ABP)')

    # Uplink parameters
    parser.add_argument('--uplinks', '-n', type=int, default=5,
                        help='Number of uplinks to send')
    parser.add_argument('--interval', '-i', type=float, default=10,
                        help='Interval between uplinks (seconds)')

    # Output
    parser.add_argument('--output', '-o',
                        help='Output file for results (JSON)')

    args = parser.parse_args()

    # Validate arguments
    if not args.scenario and not args.dev_eui:
        parser.error("Either --scenario or --dev-eui is required")

    if args.dev_eui and not args.abp and not args.app_key:
        parser.error("--app-key is required for OTAA")

    if args.abp and (not args.dev_addr or not args.nwk_s_key or not args.app_s_key):
        parser.error("ABP requires --dev-addr, --nwk-s-key, and --app-s-key")

    # Load config
    config = load_config(args.config)

    # Apply CLI overrides to config
    if 'stack' not in config:
        config['stack'] = {}
    if 'gateway' not in config:
        config['gateway'] = {}

    config['stack']['host'] = args.server
    config['stack']['gateway_udp_port'] = args.port
    config['gateway']['eui'] = args.gateway_eui

    # Create simulator
    simulator = DeviceSimulator(config)

    # Handle signals
    def signal_handler(sig, frame):
        simulator.running = False

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Run
    success = asyncio.run(simulator.run(args))
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
