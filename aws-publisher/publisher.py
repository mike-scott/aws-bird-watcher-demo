#!/usr/bin/python3

import json
import logging
import os
import subprocess
from tempfile import TemporaryDirectory
from time import sleep

import paho.mqtt.client as mqtt


def get_device_uuid():
    out = subprocess.check_output(["openssl", "x509", "-in", "/var/sota/client.pem", "-noout", "-subject"])
    line = out.decode()
    line = line.replace("subject=","")
    parts = line.split(",")
    for part in parts:
        if part.startswith("CN"):
            cn = part.split("=")[1].strip()
            return cn
    raise RuntimeError("Can't find CN from certification:" + line)


def get_client():
    with TemporaryDirectory() as tmpdir:
        chained = os.path.join(tmpdir, "chained.pem")
        with open(chained, "w") as of:
            with open("/var/sota/client.pem") as f:
                of.write(f.read())
                of.write("\n")

            with open("/srv/online-ca.pem") as f:
                of.write(f.read())
                of.write("\n")

        mqttc = mqtt.Client()
        mqttc.tls_set(ca_certs="/srv/AmazonRootCA1.pem", certfile=chained, keyfile="/var/sota/pkey.pem")
        return mqttc


def get_freemem_percent():
    total = None
    free = None
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                total = int(line.split(" ")[-2])
            elif line.startswith("MemAvailable"):
                free = int(line.split(" ")[-2])

            if total and free:
                break
    if not total:
        return 0
    return round(free / total * 100)


def main():
    uuid = get_device_uuid()
    logging.warning("Device UUID is %s", uuid)
    mqttc = get_client()
    mqttc.connect(os.environ["AWSIOT_SERVER"], 8883)
    logging.warning("Connected")

    mqttc.loop_start()
    try:
        while True:
            free = get_freemem_percent()
            data = {"device_uuid": uuid, "memory_free_percent": free}
            mqttc.publish("iot/host-metrics", json.dumps(data))
            sleep(5)
    except KeyboardInterrupt:
        logging.warning("Exiting on ctrl-c")

    mqttc.disconnect()


if "__main__" == __name__:
    main()
