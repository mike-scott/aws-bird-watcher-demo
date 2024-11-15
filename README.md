![Qualcomm Innovation Center logo](https://raw.githubusercontent.com/quic/.github/main/profile/quic_logo.png)

Welcome to the AWS re:Invent 2024 Bird Watcher demo GitHub repository

# Dataset

This demo uses the CUB-200-2011 dataset from https://www.vision.caltech.edu/datasets/cub_200_2011/ to perform object detection.

# How to build the model

A JupyterLab notebook can be used to re-create the YOLOv5 model.

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
