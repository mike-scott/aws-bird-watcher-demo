#!/bin/sh -ex

export WAYLAND_USER=weston
export XDG_RUNTIME_DIR=/run/user/63
export WAYLAND_DISPLAY=wayland-1
export OBJECT_DETECTION_CHANNEL="Detection::Demo"

exec gst-launch-1.0 -e --gst-debug=2 \
	qtimlvconverter name=stage_01_preproc mode=image-batch-non-cumulative \
	qtimlsnpe name=stage_01_inference delegate=dsp model="/var/sota/compose-apps/demo-app/yolov5m-int8.dlc" layers="<convolution_63, convolution_72, convolution_81>" \
	qtimlvdetection name=stage_01_postproc threshold=65.0 stabilization=true results=10 module=yolov5 constants="YoloV5,q-offsets=<3.0>,q-scales=<0.01692184992134571>;" labels="/var/sota/compose-apps/demo-app/CUB_200_2011.labels" \
	qtiqmmfsrc ! capsfilter caps="video/x-raw(memory:GBM),format=NV12,width=1280,height=720,framerate=30/1,compression=ubwc" ! queue ! tee name=t_split_1 \
	t_split_1. ! queue ! metamux_1. \
	t_split_1. ! queue ! stage_01_preproc. stage_01_preproc. ! queue ! stage_01_inference. stage_01_inference. ! queue ! stage_01_postproc. stage_01_postproc. ! text/x-raw ! queue ! metamux_1. \
	qtimetamux name=metamux_1 ! queue ! qtivoverlay engine=gles ! queue ! tee name=t_split_4 \
	t_split_4. ! queue ! waylandsink async=false name=display sync=false fullscreen=true \
	t_split_4. ! queue ! qtimlmetaparser module=json ! qtiredissink sync=false async=false channel="${OBJECT_DETECTION_CHANNEL}" host="172.17.0.1" port=6379
