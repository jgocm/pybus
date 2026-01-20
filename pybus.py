#!/usr/bin/env python3

import serial
import socket
import threading
import time

class Protocol:
    name: str
    def __init__(
            self,
            port: int = 14550
    ):
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
    def __init__(
            self,
            port: int
    ):
        super().__init__(port)
    
    def check(self, data):
        # TODO: implement MAVLINK message check
        # MAVLink messages start with 0xFE or 0xFD
        return True
    
# Register MAVLink protocol
ProtocolFactory.register(MAVLink.name, MAVLink)

class TEST(Protocol):
    name = "TEST"
    def __init__(
            self,
            port: int
    ):
        super().__init__(port)
    
    def check(self, data):
        # TODO: implement TEST message check
        return True

# Register TEST protocol
ProtocolFactory.register(TEST.name, TEST)

class Broker:
    def __init__(
            self,
            protocols: list
        ):
        self.protocols = protocols
    
    def check_protocols(self, data) -> list:
        valid_protocols = []
        for protocol in self.protocols:
            if protocol.check(data):
                valid_protocols.append(protocol)
        return valid_protocols

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
        name = "pybus"
    ):  
        self.name = name
        print(f"[{self.name}] Starting bridge")
        
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

        # ---- Build protocols dynamically ----
        if not protocols:
            raise ValueError("At least one protocol must be provided")

        protocol_objs = [
            ProtocolFactory.create(name, port)
            for name, port in protocols
        ]

        self.broker = Broker(protocol_objs)

    # -------------------------------------------------

    def _receiver(self):
        """Forward bytes from serial to UDP."""
        while self.running:
            try:
                self.recv()
            except Exception as e:
                print(f"[{self.name}] serial_to_udp error: {e}")
                self.running = False

    def _sender(self):
        """Forward bytes from UDP to serial."""
        while self.running:
            try:
                self.send()
            except Exception as e:
                print(f"[{self.name}] udp_to_serial error: {e}")
                self.running = False

    def recv(self):
        data = self.ser.read(self.serial_read_size)
        if not data:
            return

        valid_protocols = self.broker.check_protocols(data)
        if len(valid_protocols)==0:
            return  # silently drop unknown frames
        
        for protocol in valid_protocols:
            self.udp_sock.sendto(data, (self.udp_rx_ip, protocol.port))
    
    def send(self):
        data, _ = self.udp_sock.recvfrom(self.udp_max_packet_len)
        if data:
            self.ser.write(data)
        
    # -------------------------------------------------

    def start(self):
        """Start the serial ↔ UDP bridge."""
        print(f"[{self.name}] Starting MAVLink serial ↔ UDP bridge")

        # ---- Open Serial ----
        try:
            self.ser = serial.Serial(
                port=self.serial_port,
                baudrate=self.serial_baud,
                timeout=0,
            )
            print(
                f"[{self.name}] Serial connected: "
                f"{self.serial_port} @ {self.serial_baud}"
            )
        except Exception as e:
            raise RuntimeError(f"Failed to open serial port: {e}")

        # ---- Open UDP ----
        try:
            self.udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            self.udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.udp_sock.bind((self.udp_tx_ip, self.udp_tx_port))
        except Exception as e:
            self.ser.close()
            raise RuntimeError(f"Failed to open UDP socket: {e}")

        self.running = True

        # ---- Threads ----
        self.t_serial_to_udp = threading.Thread(
            target=self._receiver, daemon=True
        )
        self.t_udp_to_serial = threading.Thread(
            target=self._sender, daemon=True
        )

        self.t_serial_to_udp.start()
        self.t_udp_to_serial.start()

        print(
            f"[{self.name}] UDP {self.udp_tx_ip}:{self.udp_tx_port} → serial"
        )
        for protocol in self.broker.protocols:
            print(
                f"[{self.name}] Listening for {protocol.name} on UDP port {protocol.port}"
            )

    def stop(self):
        """Stop the bridge and close resources."""
        print(f"[{self.name}] Stopping bridge...")
        self.running = False

        if self.ser:
            self.ser.close()
            self.ser = None

        if self.udp_sock:
            self.udp_sock.close()
            self.udp_sock = None

        print(f"[{self.name}] Connections closed.")

# -------------------------------------------------
# Example standalone usage
# -------------------------------------------------
if __name__ == "__main__":
    protocols=[
        ("MAVLink", 14551),
        ("TEST", 14552)
        ]
    
    #bus = pybus(serial_port='/dev/ttyTHS1', udp_tx_port=14551, protocols=protocols) # PX4 port
    bus = pybus(serial_port='/dev/ttyUSB0', udp_tx_port=14550, protocols=protocols)

    try:
        bus.start()
        print(f"[{bus.name}] Bridge running. Press Ctrl+C to exit.")
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        bus.stop()
