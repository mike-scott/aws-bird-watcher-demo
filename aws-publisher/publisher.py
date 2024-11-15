#!/usr/bin/python3

import json
import logging
import os
import subprocess
from time import time
from tempfile import TemporaryDirectory

import paho.mqtt.client as mqtt
import redis

logging.basicConfig(level=os.environ.get("LOGLEVEL", "INFO"))

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

    r = redis.Redis(host="localhost", port=6379)
    p = r.pubsub()
    p.subscribe(os.environ["OBJECT_DETECTION_CHANNEL"])

    mqttc.loop_start()

    last_obj_ts = 0
    last_obj_pub = 0
    last_mem_ts = 0

    last_msg = None
    detection_msg = {"device_uuid": uuid}

    while True:
        m = p.get_message(timeout=5)
        if m is not None and m["type"] == "message":
            data = json.loads(m["data"].decode())
            objects = data.get("ObjectDetection") or []
            for object in objects:
                lbl = object.get("label")
                if object["confidence"] < 65:
                    logging.debug("Confidence too low for %s", lbl)
                else:
                    detection_msg[lbl] = 1

        now = time()

        # publish object detect events at most every 1 seconds
        if now - last_obj_ts > 1:
            if last_msg != detection_msg:
                logging.warning("Publishing: %s", detection_msg)
                mqttc.publish("iot/object-detection", json.dumps(detection_msg))
                last_msg = detection_msg
                last_obj_pub = now
            elif now - last_obj_pub > 10:
                # try to keep things fresh. you get dropped messages at times
                logging.warning("Re-Publishing: %s", detection_msg)
                mqttc.publish("iot/object-detection", json.dumps(detection_msg))
                last_obj_pub = now
            detection_msg = {"device_uuid": uuid}
            last_obj_ts = now

        # publish free memory every 10
        if False and now - last_mem_ts > 10:
            free = get_freemem_percent()
            data = {"device_uuid": uuid, "memory_free_percent": free}
            logging.info("Publishing free memory %s", data)
            mqttc.publish("iot/host-metrics", json.dumps(data))
            last_mem_ts = now


if "__main__" == __name__:
    main()
