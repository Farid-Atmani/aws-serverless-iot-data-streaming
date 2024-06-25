# Raspberry Pi IMU Data Streaming to AWS

This repository contains the necessary code and configuration files to stream data from an IMU (Inertial Measurement Unit) sensor attached to a Raspberry Pi to AWS IoT. The data is then forwarded to an Amazon Kinesis Data Stream, which triggers an AWS Lambda function to parse the binary IMU data and upload them to an S3 bucket. The infrastructure setup is managed using Terraform.

## Table of Contents

- [Overview](#Overview)
- [Architecture](#Architecture)
- [Prerequisites](#Prerequisites)
- [Configuration](#Configuration)
- [Terraform Deployment](#Terraform-Deployment)
- [Usage](#Usage)
- [Troubleshooting](#Troubleshooting)
- [License](#License)

## Overview

This project demonstrates a complete pipeline for collecting IMU data from a Raspberry Pi and processing it using various AWS services. The primary components include:

- A Raspberry Pi with an IMU sensor for data collection.
- AWS IoT for device communication and data streaming.
- An Amazon S3 bucket for storing the IoT Certificates.
- Amazon Kinesis Data Streams for handling streaming data.
- An Amazon S3 bucket for storing the Lambda deployment package.
- AWS Lambda functions for parsing the data.
- An Amazon S3 bucket for storing the parsed data.
- Terraform for infrastructure as code.

## Architecture

- Raspberry Pi: Collects IMU sensor data and sends it to AWS IoT Core message broker to the MQTT topic `raspi/data/DEVICE_ID`.
- AWS IoT: Acts as a message broker for the data sent by the Raspberry Pi.
- AWS IoT rule: Triggered when there is a payload in its topic.
- Amazon Kinesis Data Streams: Receives the data from AWS IoT and buffers it.
- AWS Lambda: Triggered by Kinesis, this function parses the binary IMU data.
- Amazon S3: The parsed data is uploaded by the lambda function to an S3 bucket for storage and further analysis.
- CloudWatch: AWS IoT and Lambda logging are enabled

![Serverless Architecture](Serverless_Architecture.png) 

## Prerequisites

- A Raspberry Pi with an IMU sensor.
- AWS account with necessary permissions.
- Terraform installed on your local machine.
- AWS CLI configured with your credentials.

## Configuration

### Creating the Deployment Package

Follow these steps to create the deployment package for your AWS Lambda function:

1. **Create a Package Folder**:
   Create a new folder to hold your Lambda function code and its dependencies.
   ```sh
   mkdir package
   ```
2. **Install Required Python Libraries**:

Install the required Python libraries into the package folder.

```sh
pip install -r requirements.txt -t package/
```
3. **Create a Zip File**:

Change to the package directory and zip the contents.

```sh
cd package
zip -r ../lambda_function.zip .
```
4. **Add Lambda Python Code to the Zip File**:

Change back to the root directory and add your Lambda function code to the zip file.

```sh
cd ..
zip -g lambda_function.zip lambda_function.py
```

### AWS IoT

Update the `iot_data_publisher.py` file with your AWS IoT endpoint and certificates paths.

## Terraform Deployment

1. Initialize Terraform:

```sh
terraform init
```

2. Plan the Deployment:

```sh
terraform plan
```

3. Apply the Deployment:

```sh
terraform apply
```

This will create the necessary AWS resources including IoT thing, IoT rule, Kinesis stream, Lambda function, S3 buckets and the necessary policies and permissions.

## Usage

1. Start the Data Stream on Raspberry Pi:

```sh
python3 iot_data_publisher.py
```

## Troubleshooting

The following resources can be useful for analyzing the source of the problem in sace of issues:

- AWS IoT Core rules and AWS Lambda can be monitored by using Amazon CloudWatch. The Terraform file includes the necessary permissions to create log groups for the IoT Core rules and Lambda function.


## License

This project is licensed under the Apache License Version 2.0 - see the LICENSE file for details.