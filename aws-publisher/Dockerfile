FROM alpine:3.20

ENV AWSIOT_SERVER="a3l1hey22pv92c-ats.iot.us-west-2.amazonaws.com"
COPY AmazonRootCA1.pem /srv/
COPY online-ca.pem /srv/

CMD ["/srv/publisher.py"]

RUN \
	apk add --no-cache openssl python3 py3-paho-mqtt

COPY publisher.py /srv/
