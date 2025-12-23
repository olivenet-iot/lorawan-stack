#!/usr/bin/env python3
"""
Traffic Generator

Generates bulk LoRaWAN traffic for load testing and stress testing.

Usage:
    python traffic_generator.py --devices 100 --rate 10 --duration 300
    python traffic_generator.py --scenario scenarios/stress_test.yml

Arguments:
    --devices    Number of virtual devices
    --rate       Uplinks per second (total)
    --duration   Test duration in seconds
    --scenario   Scenario file

Features:
    - Parallel device management (asyncio)
    - Configurable uplink rate
    - Progress bar
    - Real-time statistics
    - Memory-efficient for 5000+ devices
    - Result export (JSON, CSV)
"""

import argparse
import asyncio
import base64
import json
import os
import sys
import signal
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List

import yaml
from colorama import init, Fore, Style
from tqdm import tqdm

# Initialize colorama
init()

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent))

from lib.device import VirtualDevice, eui_from_string, key_from_string
from lib.gateway import VirtualGateway, GatewayConfig, GatewayLocation
from lib.packet_forwarder import TxPacket


@dataclass
class DeviceState:
    """Lightweight device state for memory efficiency"""
    dev_eui: bytes
    join_eui: bytes
    app_key: bytes
    dev_addr: Optional[bytes] = None
    nwk_s_key: Optional[bytes] = None
    app_s_key: Optional[bytes] = None
    fcnt_up: int = 0
    is_joined: bool = False


@dataclass
class TestStats:
    """Test statistics"""
    devices_total: int = 0
    devices_joined: int = 0
    devices_failed: int = 0
    uplinks_sent: int = 0
    uplinks_acked: int = 0
    join_requests: int = 0
    join_accepts: int = 0
    errors: int = 0
    start_time: float = 0
    end_time: float = 0

    @property
    def join_success_rate(self) -> float:
        if self.join_requests == 0:
            return 0.0
        return self.devices_joined / self.join_requests * 100

    @property
    def uplink_success_rate(self) -> float:
        if self.uplinks_sent == 0:
            return 0.0
        return self.uplinks_acked / self.uplinks_sent * 100

    @property
    def duration(self) -> float:
        if self.end_time == 0:
            return time.time() - self.start_time
        return self.end_time - self.start_time

    @property
    def uplinks_per_second(self) -> float:
        if self.duration == 0:
            return 0.0
        return self.uplinks_sent / self.duration


class TrafficGenerator:
    """High-performance traffic generator"""

    def __init__(self, config: dict):
        self.config = config
        self.gateway: Optional[VirtualGateway] = None
        self.stats = TestStats()
        self.running = False

        # Device management
        self.devices: Dict[str, VirtualDevice] = {}
        self._pending_joins: Dict[str, asyncio.Event] = {}
        self._join_accepts: Dict[str, bytes] = {}

        # Rate limiting
        self._uplink_semaphore: Optional[asyncio.Semaphore] = None

    def log(self, message: str, level: str = "INFO"):
        """Log a message"""
        timestamp = datetime.now().strftime('%H:%M:%S')
        colors = {
            "ERROR": Fore.RED,
            "WARN": Fore.YELLOW,
            "SUCCESS": Fore.GREEN,
            "INFO": Fore.WHITE,
        }
        color = colors.get(level, Fore.WHITE)
        print(f"{Fore.BLUE}[{timestamp}]{Style.RESET_ALL} {color}{message}{Style.RESET_ALL}")

    async def setup_gateway(self) -> bool:
        """Set up virtual gateway"""
        gw_config = self.config.get('gateway', {})
        stack_config = self.config.get('stack', {})

        config = GatewayConfig(
            eui=gw_config.get('eui', 'AA555A0000000001'),
            server_host=stack_config.get('host', 'localhost'),
            server_port=stack_config.get('gateway_udp_port', 1700),
        )

        self.gateway = VirtualGateway(config=config)
        self.gateway.on_downlink = self._on_downlink

        connected = await self.gateway.connect()
        if not connected:
            self.log("Failed to connect gateway", "ERROR")
            return False

        self.log("Gateway connected", "SUCCESS")
        return True

    def _on_downlink(self, txpk: TxPacket):
        """Handle downlink"""
        try:
            payload = base64.b64decode(txpk.data)
            mhdr = payload[0]
            mtype = (mhdr >> 5) & 0x07

            if mtype == 1:  # Join Accept
                self.stats.join_accepts += 1
                for dev_eui, event in self._pending_joins.items():
                    if not event.is_set():
                        self._join_accepts[dev_eui] = payload
                        event.set()
                        break
            else:
                self.stats.uplinks_acked += 1
        except Exception:
            pass

    def _generate_devices(self, count: int, dev_eui_start: str, app_key: str) -> List[VirtualDevice]:
        """Generate virtual devices"""
        devices = []
        prefix = bytes.fromhex(dev_eui_start.replace(':', ''))

        for i in range(count):
            # Generate DevEUI
            dev_eui = prefix[:4] + i.to_bytes(4, 'big')

            device = VirtualDevice(
                dev_eui=dev_eui,
                join_eui=bytes(8),
                app_key=key_from_string(app_key),
            )
            devices.append(device)

        return devices

    async def join_device(self, device: VirtualDevice, timeout: float = 30.0) -> bool:
        """Join a single device"""
        dev_eui_str = device.dev_eui.hex().upper()

        event = asyncio.Event()
        self._pending_joins[dev_eui_str] = event

        try:
            # Send join request
            join_request = device.build_join_request()
            self.stats.join_requests += 1

            await self.gateway.send_uplink(
                join_request,
                self.gateway.simulate_radio_params()
            )

            # Wait for join accept
            try:
                await asyncio.wait_for(event.wait(), timeout=timeout)
            except asyncio.TimeoutError:
                self.stats.devices_failed += 1
                return False

            # Process join accept
            if dev_eui_str in self._join_accepts:
                device.process_join_accept(self._join_accepts[dev_eui_str])
                self.stats.devices_joined += 1
                return True

            self.stats.devices_failed += 1
            return False

        finally:
            del self._pending_joins[dev_eui_str]
            if dev_eui_str in self._join_accepts:
                del self._join_accepts[dev_eui_str]

    async def join_devices_batch(
        self,
        devices: List[VirtualDevice],
        batch_size: int = 100,
        batch_delay: float = 5.0,
        timeout: float = 30.0
    ):
        """Join devices in batches"""
        total = len(devices)
        self.stats.devices_total = total

        self.log(f"Joining {total} devices in batches of {batch_size}...")

        with tqdm(total=total, desc="Joining", unit="dev") as pbar:
            for i in range(0, total, batch_size):
                if not self.running:
                    break

                batch = devices[i:i+batch_size]

                # Join batch in parallel
                tasks = [self.join_device(dev, timeout) for dev in batch]
                results = await asyncio.gather(*tasks, return_exceptions=True)

                # Count successes
                successes = sum(1 for r in results if r is True)
                pbar.update(len(batch))
                pbar.set_postfix({
                    'joined': self.stats.devices_joined,
                    'failed': self.stats.devices_failed
                })

                # Delay between batches
                if i + batch_size < total and self.running:
                    await asyncio.sleep(batch_delay)

    async def send_traffic(
        self,
        devices: List[VirtualDevice],
        duration: float,
        rate: float,  # uplinks per second
    ):
        """Send continuous traffic"""
        joined_devices = [d for d in devices if d.is_joined]
        if not joined_devices:
            self.log("No joined devices to send traffic", "ERROR")
            return

        self.log(f"Generating traffic from {len(joined_devices)} devices at {rate} uplinks/sec...")

        interval = 1.0 / rate
        end_time = time.time() + duration

        with tqdm(total=int(duration), desc="Traffic", unit="s") as pbar:
            last_update = time.time()

            while self.running and time.time() < end_time:
                # Select random device
                device = joined_devices[int(time.time() * 1000) % len(joined_devices)]

                # Send uplink
                try:
                    payload = os.urandom(10)
                    uplink = device.build_uplink(1, payload)
                    await self.gateway.send_uplink(
                        uplink,
                        self.gateway.simulate_radio_params()
                    )
                    self.stats.uplinks_sent += 1
                except Exception as e:
                    self.stats.errors += 1

                # Rate limiting
                await asyncio.sleep(interval)

                # Update progress
                now = time.time()
                if now - last_update >= 1.0:
                    pbar.update(1)
                    pbar.set_postfix({
                        'uplinks': self.stats.uplinks_sent,
                        'rate': f'{self.stats.uplinks_per_second:.1f}/s'
                    })
                    last_update = now

    async def run(
        self,
        device_count: int,
        duration: float,
        rate: float,
        dev_eui_start: str = "70B3D57ED0010000",
        app_key: str = "00112233445566778899AABBCCDDEEFF",
        join_batch_size: int = 100,
        join_batch_delay: float = 5.0,
    ) -> TestStats:
        """Run the traffic generator"""
        self.running = True
        self.stats.start_time = time.time()

        print()
        print(f"{Fore.CYAN}{Style.BRIGHT}Traffic Generator - {device_count} devices, {rate} uplinks/sec{Style.RESET_ALL}")
        print("=" * 60)

        # Setup gateway
        if not await self.setup_gateway():
            return self.stats

        try:
            # Generate devices
            self.log(f"Generating {device_count} virtual devices...")
            devices = self._generate_devices(device_count, dev_eui_start, app_key)

            # Phase 1: Join devices
            await self.join_devices_batch(
                devices,
                batch_size=join_batch_size,
                batch_delay=join_batch_delay,
            )

            if not self.running:
                return self.stats

            print()
            self.log(f"Join complete: {self.stats.devices_joined}/{device_count} devices ({self.stats.join_success_rate:.1f}%)")

            # Phase 2: Generate traffic
            if duration > 0:
                print()
                await self.send_traffic(devices, duration, rate)

        finally:
            self.stats.end_time = time.time()
            await self.gateway.disconnect()

        return self.stats

    def print_summary(self):
        """Print test summary"""
        print()
        print(f"{Fore.CYAN}{Style.BRIGHT}Test Summary{Style.RESET_ALL}")
        print("=" * 60)
        print(f"Duration:             {self.stats.duration:.1f}s")
        print(f"Devices joined:       {self.stats.devices_joined}/{self.stats.devices_total} ({self.stats.join_success_rate:.1f}%)")
        print(f"Uplinks sent:         {self.stats.uplinks_sent}")
        print(f"Uplinks/sec:          {self.stats.uplinks_per_second:.1f}")
        print(f"Errors:               {self.stats.errors}")
        print()


def load_config(config_path: str) -> dict:
    """Load configuration from YAML file"""
    path = Path(config_path)
    if path.exists():
        with open(path, 'r') as f:
            return yaml.safe_load(f)
    return {}


def main():
    parser = argparse.ArgumentParser(
        description="LoRaWAN Traffic Generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument('--config', '-c', default='config.yml',
                        help='Configuration file')
    parser.add_argument('--server', default='localhost',
                        help='TTS server address')
    parser.add_argument('--port', type=int, default=1700,
                        help='UDP port')
    parser.add_argument('--gateway-eui', default='AA555A0000000001',
                        help='Gateway EUI')
    parser.add_argument('--scenario', '-s',
                        help='Scenario file')
    parser.add_argument('--devices', '-d', type=int, default=100,
                        help='Number of devices')
    parser.add_argument('--rate', '-r', type=float, default=10,
                        help='Uplinks per second')
    parser.add_argument('--duration', type=float, default=60,
                        help='Test duration (seconds)')
    parser.add_argument('--dev-eui-start', default='70B3D57ED0010000',
                        help='Starting DevEUI')
    parser.add_argument('--app-key', default='00112233445566778899AABBCCDDEEFF',
                        help='Application Key')
    parser.add_argument('--output', '-o',
                        help='Output file (JSON)')

    args = parser.parse_args()

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

    # Load scenario if provided
    if args.scenario:
        with open(args.scenario, 'r') as f:
            scenario = yaml.safe_load(f)
            args.devices = scenario.get('device_count', args.devices)
            test = scenario.get('test', {})
            args.duration = test.get('duration', args.duration)
            args.rate = test.get('uplink_rate', args.rate)

    # Create generator
    generator = TrafficGenerator(config)

    # Handle signals
    def signal_handler(sig, frame):
        print("\nStopping...")
        generator.running = False

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Run
    stats = asyncio.run(generator.run(
        device_count=args.devices,
        duration=args.duration,
        rate=args.rate,
        dev_eui_start=args.dev_eui_start,
        app_key=args.app_key,
    ))

    generator.print_summary()

    # Save results
    if args.output:
        results = {
            'timestamp': datetime.utcnow().isoformat(),
            'devices_total': stats.devices_total,
            'devices_joined': stats.devices_joined,
            'devices_failed': stats.devices_failed,
            'join_success_rate': stats.join_success_rate,
            'uplinks_sent': stats.uplinks_sent,
            'uplinks_per_second': stats.uplinks_per_second,
            'duration': stats.duration,
            'errors': stats.errors,
        }
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        print(f"Results saved to {args.output}")

    sys.exit(0 if stats.devices_joined > 0 else 1)


if __name__ == '__main__':
    main()
