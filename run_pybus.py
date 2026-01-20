#!/usr/bin/env python3

import json
import time
import signal
import sys

from pybus import pybus   # or whatever your module name is


def load_config(path):
    with open(path, "r") as f:
        return json.load(f)


def main():
    config = load_config("configs/rc_drone.json")

    buses = []

    # ---- Create and start all pybus instances ----
    for cfg in config["instances"]:
        print(f"[launcher] Starting instance: {cfg.get('name', 'unnamed')}")

        bus = pybus(
            serial_port=cfg.get("serial_port", "/dev/ttyUSB0"),
            serial_baud=cfg.get("serial_baud", 57600),
            serial_read_size=cfg.get("serial_read_size", 4096),
            udp_rx_ip=cfg.get("udp_rx_ip", "127.0.0.1"),
            udp_tx_ip=cfg.get("udp_tx_ip", "127.0.0.1"),
            udp_tx_port=cfg.get("udp_tx_port", 14550),
            udp_packet_len=cfg.get("udp_packet_len", 65535),
            protocols=cfg["protocols"],
        )

        bus.start()
        buses.append(bus)

    print(f"[launcher] {len(buses)} pybus instances running")

    # ---- Graceful shutdown handling ----
    def shutdown(signum, frame):
        print("\n[launcher] Shutting down...")
        for bus in buses:
            bus.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    # ---- Keep main thread alive ----
    while True:
        time.sleep(1)


if __name__ == "__main__":
    main()
