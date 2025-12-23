#!/usr/bin/env python3
"""
Gateway Simulator

Standalone tool to simulate a LoRaWAN gateway connecting to TTS.
Useful for testing gateway server connectivity without real hardware.

Usage:
    python gateway_simulator.py [--config config.yml] [--eui AA555A...]

Examples:
    # Default config
    python gateway_simulator.py

    # Custom EUI
    python gateway_simulator.py --eui AA555A0000000099

    # Interactive mode (allows manual uplink injection)
    python gateway_simulator.py --interactive

    # Test mode (connect, verify, exit)
    python gateway_simulator.py --test-only
"""

import argparse
import asyncio
import base64
import sys
import signal
from datetime import datetime
from pathlib import Path

import yaml
from colorama import init, Fore, Style

# Initialize colorama
init()

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent))

from lib.gateway import VirtualGateway, GatewayConfig, GatewayLocation, RadioParams
from lib.packet_forwarder import TxPacket


class GatewaySimulator:
    """Gateway simulator with interactive capabilities"""

    def __init__(self, config: dict, interactive: bool = False, test_only: bool = False):
        self.config = config
        self.interactive = interactive
        self.test_only = test_only
        self.gateway: VirtualGateway = None
        self.running = False

    def log(self, message: str, level: str = "INFO"):
        """Log a message with timestamp"""
        timestamp = datetime.now().strftime('%H:%M:%S')

        if level == "ERROR":
            color = Fore.RED
        elif level == "WARN":
            color = Fore.YELLOW
        elif level == "SUCCESS":
            color = Fore.GREEN
        elif level == "DEBUG":
            color = Fore.CYAN
        else:
            color = Fore.WHITE

        print(f"{Fore.BLUE}[{timestamp}]{Style.RESET_ALL} {color}{message}{Style.RESET_ALL}")

    def on_downlink(self, txpk: TxPacket):
        """Handle received downlink"""
        self.log(f"← Downlink received:", "SUCCESS")
        self.log(f"  Frequency: {txpk.freq} MHz")
        self.log(f"  Data Rate: {txpk.datr}")
        self.log(f"  Payload: {txpk.data[:50]}..." if len(txpk.data) > 50 else f"  Payload: {txpk.data}")

    def on_connected(self):
        """Handle connection event"""
        self.log("Gateway connected successfully", "SUCCESS")

    async def run(self):
        """Run the gateway simulator"""
        gw_config = self.config.get('gateway', {})
        stack_config = self.config.get('stack', {})

        # Create gateway configuration
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
            frequency_plan=gw_config.get('frequency_plan', 'EU_863_870'),
            location=location,
            pull_interval=gw_config.get('pull_interval', 30.0),
        )

        # Create gateway
        self.gateway = VirtualGateway(config=config)
        self.gateway.on_downlink = self.on_downlink
        self.gateway.on_connected = self.on_connected

        self.log(f"Gateway {config.eui} starting...")
        self.log(f"Connecting to {config.server_host}:{config.server_port}")

        # Connect
        connected = await self.gateway.connect()

        if not connected:
            self.log("Failed to connect (no PULL_ACK received)", "ERROR")
            return False

        self.log("✓ PULL_ACK received", "SUCCESS")

        if self.test_only:
            self.log("Test mode: connection verified, exiting")
            await self.gateway.disconnect()
            return True

        self.running = True

        # Main loop
        try:
            if self.interactive:
                await self._interactive_loop()
            else:
                await self._status_loop()
        except asyncio.CancelledError:
            pass
        finally:
            self.log("Shutting down...")
            await self.gateway.disconnect()

        return True

    async def _status_loop(self):
        """Non-interactive status loop"""
        status_interval = self.config.get('gateway', {}).get('status_interval', 30)

        while self.running:
            await asyncio.sleep(status_interval)
            stats = self.gateway.get_stats()
            self.log(f"Stats: Uplinks={stats['uplinks_sent']}, ACKs={stats['uplinks_acked']}, Downlinks={stats['downlinks_received']}")

    async def _interactive_loop(self):
        """Interactive command loop"""
        self.log("Interactive mode. Commands:")
        self.log("  status    - Show gateway status")
        self.log("  uplink    - Send a test uplink")
        self.log("  quit      - Exit")
        self.log("")

        loop = asyncio.get_event_loop()

        while self.running:
            try:
                # Read command
                cmd = await loop.run_in_executor(None, input, "> ")
                cmd = cmd.strip().lower()

                if cmd == "quit" or cmd == "exit":
                    self.running = False
                    break
                elif cmd == "status":
                    stats = self.gateway.get_stats()
                    self.log(f"Gateway: {stats['eui']}")
                    self.log(f"  Connected: {stats['connected']}")
                    self.log(f"  Uplinks sent: {stats['uplinks_sent']}")
                    self.log(f"  Uplinks ACKed: {stats['uplinks_acked']}")
                    self.log(f"  Downlinks: {stats['downlinks_received']}")
                    self.log(f"  PULL ACKs: {stats['pull_acks']}")
                elif cmd == "uplink":
                    # Send a test uplink (random data)
                    import os
                    test_payload = os.urandom(20)
                    await self.gateway.send_uplink(
                        test_payload,
                        self.gateway.simulate_radio_params()
                    )
                    self.log(f"→ Test uplink sent ({len(test_payload)} bytes)")
                elif cmd:
                    self.log(f"Unknown command: {cmd}", "WARN")

            except EOFError:
                break


def load_config(config_path: str) -> dict:
    """Load configuration from YAML file"""
    path = Path(config_path)
    if not path.exists():
        # Try local config
        local_path = path.with_suffix('.local.yml')
        if local_path.exists():
            path = local_path
        else:
            print(f"Warning: Config file not found: {config_path}")
            return {}

    with open(path, 'r') as f:
        return yaml.safe_load(f)


def main():
    parser = argparse.ArgumentParser(
        description="LoRaWAN Gateway Simulator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        '--config', '-c',
        default='config.yml',
        help='Configuration file (default: config.yml)'
    )
    parser.add_argument(
        '--eui',
        help='Override gateway EUI'
    )
    parser.add_argument(
        '--server',
        help='Override server host'
    )
    parser.add_argument(
        '--port', '-p',
        type=int,
        help='Override server port'
    )
    parser.add_argument(
        '--interactive', '-i',
        action='store_true',
        help='Enable interactive mode'
    )
    parser.add_argument(
        '--test-only', '-t',
        action='store_true',
        help='Test connection and exit'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Enable debug output'
    )

    args = parser.parse_args()

    # Load config
    config = load_config(args.config)

    # Apply overrides
    if args.eui:
        if 'gateway' not in config:
            config['gateway'] = {}
        config['gateway']['eui'] = args.eui

    if args.server:
        if 'stack' not in config:
            config['stack'] = {}
        config['stack']['host'] = args.server

    if args.port:
        if 'stack' not in config:
            config['stack'] = {}
        config['stack']['gateway_udp_port'] = args.port

    # Create simulator
    simulator = GatewaySimulator(
        config=config,
        interactive=args.interactive,
        test_only=args.test_only
    )

    # Handle signals
    def signal_handler(sig, frame):
        simulator.running = False

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Run
    success = asyncio.run(simulator.run())
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
