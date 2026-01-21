from pybus import pybus
import time 

if __name__ == "__main__":
    protocols=[
            ("mavlink", 14551),
            ("test", 14552),
        ]
    bus = pybus(protocols=protocols)

    try:
        bus.start()
        print("[pybus] Bridge running. Press Ctrl+C to exit.")
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        bus.stop()