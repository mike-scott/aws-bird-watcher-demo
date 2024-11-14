import logging
import os
from queue import Queue

from awsiot import mqtt5_client_builder
from awscrt import mqtt5, auth
from flask import Flask, Response

logging.basicConfig(level=os.environ.get("LOGLEVEL", "INFO"))


class IotSub:
    TIMEOUT = 10
    message_topic = "iot/object-detection"
    signing_region = "us-west-2"
    client = None

    queue = Queue()

    @classmethod
    def start(cls):
        credentials_provider = auth.AwsCredentialsProvider.new_default_chain()

        def on_message(packet_data):
            cls.queue.put(packet_data.publish_packet.payload)

        cls.client = mqtt5_client_builder.websockets_with_default_aws_signing(
            endpoint="a3l1hey22pv92c-ats.iot.us-west-2.amazonaws.com",
            region=cls.signing_region,
            credentials_provider=credentials_provider,
            on_publish_received=on_message,
        )

        logging.warning("Starting pubsub client...")
        cls.client.start()

        logging.warning("Subscribing to topic %s", cls.message_topic)
        subscribe_future = cls.client.subscribe(
            subscribe_packet=mqtt5.SubscribePacket(
                subscriptions=[
                    mqtt5.Subscription(
                        topic_filter=cls.message_topic, qos=mqtt5.QoS.AT_LEAST_ONCE
                    )
                ]
            )
        )
        suback = subscribe_future.result(cls.TIMEOUT)
        logging.warning("Subscribed with %s", suback.reason_codes)

    @classmethod
    def stop(cls):
        logging.warning("Stopping pubsub client")
        cls.client.stop()


app = Flask(__name__)


@app.route("/")
def helloworld():
    return open("index.html")


@app.route("/stream")
def stream():
    def eventStream():
        data = None
        while True:
            data = IotSub.queue.get()
            if data:
                yield b"data: " + data + b"\n\n"

    return Response(eventStream(), mimetype="text/event-stream")


if __name__ == "__main__":
    port = os.environ.get("PORT", "8000")
    IotSub.start()
    app.run(port=int(port), host="0.0.0.0")
