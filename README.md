# pybus
A python class that implements a bridge between an UDP and a Serial port

![PYBUS](resources/drone_architecture-comm.png "PYBUS")

## Dependencies
pybus only uses common Python packages, such as: serial, socker, threading, time, argparse, json, sys and logging.

```
pip install pyserial
```

Some devices might need to be configured to give permission to scripts to access serial ports:
```
sudo usermod -a -G dialout $USER
```

Reboot or logout for this change to take effect.

The bash scripts for startup and systemd installation also use jq to open json file.
```
sudo apt install jq
```

## Configs
pybus requires a configuration file such as the ones provided in the configs folder. It must be filled with your list of desired pybus instances that should be executed, where instance contains the following arguments:
- name: a name/label for the given instance
- serial_port: which serial you wish it to connect to
- udp_tx_port: which udp port will be used to publish data to the serial port
- protocols: a list of protocols and ports, so that messages from each protocol get published to their correspondent ports (wip: for now, all messages are published to all ports)

TODO:
- implement the broker that filters messages for their correct ports based on their protocols' checkers

## Running
This repo provides scripts to install it as a systemd service, but it can also be executed as a simple Python script or using the start_pybus.sh script.

### Running with Python
When running directly from Python, only a single instance can be executed at a time:
`python3 pybus.py --config <path-to-your-config-file> --instance <instance-name-from-config-file>`

Note that the instance name must match the one from the given config file.

If you desire to run more instances, open another terminal for it.

Also note that you can't have more than one instance connected to the same serial port.

### Running with bash script
The bash script runs all instances from a given config file. Run it with:
`./start_pybus <path-to-your-config-file>`

Note that the bash script should be called from the same folder that contains the pybus.py script.

If your pybus is running correctly you should see the following message in the terminal:
```
✔ Instance 'radio_bus' is running (PID: 89575)
```

If not:

```
✘ Instance 'radio_bus' is NOT running
```

The pybus instances will be running in background. Therefore, this repo provides another script to stop them:
`./stop_pybus`

TODO: 
- create an alias to run pybus Python script
- make an option to have log files in a given directory

### Running as systemd service
This repo provides a script to install pybus as a systemd service. It uses templated services and creates instances that correspond to each instance of a given config file. The installation can be executed with:
```
sudo ./install_service.sh <path-to-config-file>
```

This script will:
- Update config and pybus.py service's files
- Create a .service template file
- Remove obsolete pybus service instances
- Enable pybus instances from the names given in the config file
- Reload systemd
- If ran with "-s" flag at the end, it will also start the services: `sudo ./install_service.sh <path-to-config-file> -s`

The services' logs can be checked in the journalctl with:
```
journalctl -u pybus@<instance-name> -f
```

### Limit log file size for systemd

Edit journald config:
`sudo nano /etc/systemd/journald.conf`

Uncomment or add these lines:
```
[Journal]
SystemMaxUse=100M
SystemKeepFree=200M
MaxFileSize=10M
```

Restart journald:
`sudo systemctl restart systemd-journald`

Verify current usage:
`journalctl --disk-usage`