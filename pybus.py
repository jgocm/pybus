#!/usr/bin/env python3

import serial
import socket
import threading
import time
import argparse
import json
import logging
import sys
from pymavlink import mavutil


# -------------------------------------------------
# Logging setup
# -------------------------------------------------

def setup_logger(name: str):
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)

    if logger.handlers:
        return logger

    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        "%Y-%m-%d %H:%M:%S",
    )

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    logger.addHandler(handler)
    logger.propagate = False

    return logger


class StreamToLogger:
    def __init__(self, logger, level):
        self.logger = logger
        self.level = level

    def write(self, message):
        message = message.strip()
        if message:
            self.logger.log(self.level, message)

    def flush(self):
        pass

# -------------------------------------------------
# Protocols
# -------------------------------------------------

class Protocol:
    name: str

    def __init__(self, port: int = 14550):
        self.port = port

    def check(self, data):
        pass


class ProtocolFactory:
    _registry = {}

    @classmethod
    def register(cls, name: str, protocol_cls):
        cls._registry[name.lower()] = protocol_cls

    @classmethod
    def create(cls, name: str, port: int) -> Protocol:
        key = name.lower()
        if key not in cls._registry:
            raise ValueError(f"Unknown protocol: {name}")
        return cls._registry[key](port)


class MAVLink(Protocol):
    name = "MAVLink"
    mav = mavutil.mavlink.MAVLink(None)

    def check(self, data: bytes) -> bool:
        self.is_mavlink_message(data)
        return True

    def is_mavlink_message(self, data: bytes) -> bool:
        """
        Check if incoming bytes contain a valid MAVLink message.
        Returns True if a MAVLink frame is detected.
        """
        for b in data:
            msg = self.mav.parse_char(bytes([b]))
            if msg:
                return True

        return False
    
    def is_not_radio_status(self, msg) -> bool:
        return msg.get_type() != "RADIO_STATUS"


ProtocolFactory.register(MAVLink.name, MAVLink)


class TEST(Protocol):
    name = "TEST"

    def check(self, data):
        return True


ProtocolFactory.register(TEST.name, TEST)


# -------------------------------------------------
# Broker
# -------------------------------------------------

class Broker:
    def __init__(self, protocols: list):
        self.protocols = protocols

    def check_protocols(self, data) -> list:
        return [p for p in self.protocols if p.check(data)]


# -------------------------------------------------
# pybus
# -------------------------------------------------

class pybus:
    def __init__(
        self,
        serial_port="/dev/ttyUSB0",
        serial_baud=57600,
        serial_read_size=4096,
        udp_rx_ip="127.0.0.1",
        udp_tx_ip="127.0.0.1",
        udp_tx_port=14550,
        udp_packet_len=65535,
        protocols=None,
        name="pybus",
        log_file=None,
    ):
        self.name = name
        self.logger = setup_logger(name)

        self.logger.info("Initializing bridge")

        self.serial_port = serial_port
        self.serial_baud = serial_baud
        self.serial_read_size = serial_read_size

        self.udp_rx_ip = udp_rx_ip
        self.udp_tx_ip = udp_tx_ip
        self.udp_tx_port = udp_tx_port
        self.udp_max_packet_len = udp_packet_len

        self.ser = None
        self.udp_sock = None
        self.running = False

        self.t_serial_to_udp = None
        self.t_udp_to_serial = None

        if not protocols:
            raise ValueError("At least one protocol must be provided")

        self.broker = Broker(
            [ProtocolFactory.create(name, port) for name, port in protocols]
        )

    # -------------------------------------------------

    def _receiver(self):
        while self.running:
            try:
                self.recv()
            except Exception:
                self.logger.exception("serial → UDP thread crashed")
                self.running = False

    def _sender(self):
        while self.running:
            try:
                self.send()
            except Exception:
                self.logger.exception("UDP → serial thread crashed")
                self.running = False

    def recv(self):
        data = self.ser.read(self.serial_read_size)
        if not data:
            return

        for protocol in self.broker.check_protocols(data):
            self.udp_sock.sendto(data, (self.udp_rx_ip, protocol.port))

    def send(self):
        data, _ = self.udp_sock.recvfrom(self.udp_max_packet_len)
        
        self.broker.protocols[0].check(data)

        if data:
            self.ser.write(data)

    # -------------------------------------------------

    def start(self):
        self.logger.info("Starting serial ↔ UDP bridge")

        try:
            self.ser = serial.Serial(
                port=self.serial_port,
                baudrate=self.serial_baud,
                timeout=0,
            )
            self.logger.info(
                "Serial connected: %s @ %d",
                self.serial_port,
                self.serial_baud,
            )
        except Exception:
            self.logger.exception("Failed to open serial port")
            raise

        try:
            self.udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            self.udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.udp_sock.bind((self.udp_tx_ip, self.udp_tx_port))
        except Exception:
            self.logger.exception("Failed to open UDP socket")
            self.ser.close()
            raise

        self.running = True
        self.t_serial_to_udp = threading.Thread(
            target=self._receiver, daemon=True
        )
        self.t_udp_to_serial = threading.Thread(
            target=self._sender, daemon=True
        )

        self.t_serial_to_udp.start()
        self.t_udp_to_serial.start()

        self.logger.info(
            "UDP %s:%d → serial",
            self.udp_tx_ip,
            self.udp_tx_port,
        )

        for protocol in self.broker.protocols:
            self.logger.info(
                "Listening for %s on UDP port %d",
                protocol.name,
                protocol.port,
            )

    def stop(self):
        self.logger.info("Stopping bridge")
        self.running = False

        if self.ser:
            self.ser.close()
            self.ser = None

        if self.udp_sock:
            self.udp_sock.close()
            self.udp_sock = None

        self.logger.info("Connections closed")


# -------------------------------------------------
# Runner from JSON config
# -------------------------------------------------

def run_from_config(config_path, instance_name):
    log_file = f"logs/{instance_name}.log"

    # Root logger (captures everything)
    root_logger = setup_logger(instance_name)

    # Redirect stdout / stderr
    sys.stdout = StreamToLogger(root_logger, logging.INFO)
    sys.stderr = StreamToLogger(root_logger, logging.ERROR)

    with open(config_path, "r") as f:
        cfg = json.load(f)

    instance = next(
        i for i in cfg["instances"]
        if i.get("name") == instance_name
    )

    bus = pybus(
        serial_port=instance.get("serial_port", "/dev/ttyUSB0"),
        serial_baud=instance.get("serial_baud", 57600),
        serial_read_size=instance.get("serial_read_size", 4096),
        udp_rx_ip=instance.get("udp_rx_ip", "127.0.0.1"),
        udp_tx_ip=instance.get("udp_tx_ip", "127.0.0.1"),
        udp_tx_port=instance.get("udp_tx_port", 14550),
        udp_packet_len=instance.get("udp_packet_len", 65535),
        protocols=instance["protocols"],
        name=instance_name,
        log_file=log_file,
    )

    bus.start()
    bus.logger.info("Instance running")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        bus.stop()


# -------------------------------------------------
# Main
# -------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--instance", required=True)
    args = parser.parse_args()

    run_from_config(args.config, args.instance)
