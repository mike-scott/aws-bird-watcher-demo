![Qualcomm Innovation Center logo](https://raw.githubusercontent.com/quic/.github/main/profile/quic_logo.png)

Welcome to the AWS re:Invent 2024 Bird Watcher demo GitHub repository.

# Object Detection AI Model

This demonstration uses the YOLOv5 Object Detection model created by Ultralytics:  
https://github.com/ultralytics/yolov5

# Dataset

The bird data used for training is the Caltech / UCSD Birds CUB-200-2011[^1] dataset here:  
https://www.vision.caltech.edu/datasets/cub_200_2011/

# Build the model with AWS SageMaker

- Start an AWS SageMaker JupyterLab instance
  - Instance: ml.p3.2xlarge
  - Image: SageMaker Distribution 2.1.0
- Once the instance is open, use the "Git Clone" tool and import this github repo
- Open the Jupyter notebook file prepare-dataset-and-train.ipynb and execute each step
- Once complete download the following artifacts:
  - CUB_200_2011.labels
  - yolov5m-fp16.tflite
  - calibration.tar.gz

# Convert the TFLite formatted AI Model into a quantized DLC model

- These instructions are performed on a Linux host
- Follow the Setup instructions for the Snapdragon Neural Processing Engine SDK:
  - https://docs.qualcomm.com/bundle/publicresource/topics/80-63442-2/setup.html
  - Once the installation is complete also install the requirements.txt in this repo
    - python3 -m pip install -r requirements.txt
- The following steps should be run from same location as the downloaded artifacts
- Extract the calibration data
  - tar -xf calibration.tar.gz
  - python3 $SNPE_ROOT/examples/Models/InceptionV3/scripts/create_inceptionv3_raws.py --dest calibration --size 320 --img_folder calibration
  - python3 $SNPE_ROOT/examples/Models/InceptionV3/scripts/create_file_list.py --input_dir "calibration" --output_filename "yolov5m.dlc.conf" --ext_pattern "*.raw"
- Convert the <model>.tflite file into the Deep Learning Container format (DLC) with the following command:
  - Doc: https://docs.qualcomm.com/bundle/publicresource/topics/80-63442-2/model_conv_tflite.html
  - snpe-tflite-to-dlc --input_network yolov5m-fp16.tflite
- Quantize the <model>.dlc with the following command:
  - Doc: https://docs.qualcomm.com/bundle/publicresource/topics/80-63442-2/model_conversion.html
  - snpe-dlc-quantize --input_list=yolov5m.dlc.conf --input_dlc=yolov5m-fp16.dlc --output_dlc=yolov5m-int8.dlc

# Cloud Setup

AWS is provisioned with an MQTT endpoint collecting data from the edge devices and representing it on a dashboard which shows
what objects have been detected.  There is a terraform file which can be sed to set this up.

# Edge Device Setup

## Hardware

The edge application runs on a Qualcomm® RB3 Gen 2 Dev Kit https://www.qualcomm.com/developer/hardware/rb3-gen-2-development-kit

## Software

The OS on the edge device is based on Qualcomm Linux v1.2 and the Qualcomm Intelligent Multimedia Product SDK (QIMSDK)
https://www.qualcomm.com/developer/software/qualcomm-linux
https://www.qualcomm.com/developer/software/qualcomm-intelligent-multimedia-sdk

## Device Management

Device management provided by https://foundries.io/

# References

[^1]: Wah, C. and Branson, S. and Welinder, P. and Perona, P. and Belongie, S., 2011.  California Institute of Technology.  CNS-TR-2011-001  
https://www.vision.caltech.edu/datasets/cub_200_2011/
