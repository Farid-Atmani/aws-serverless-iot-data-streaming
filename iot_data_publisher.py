import os
import json
import struct
import logging 
import boto3
import subprocess
from mpu6050 import mpu6050
import paho.mqtt.client as mqtt
from botocore.exceptions import NoCredentialsError, PartialCredentialsError, ClientError
import ssl
import time


def get_rpi_serial():
    try:
        with open("/proc/cpuinfo", "r") as f:
            for line in f:
                if line.startswith("Serial"):
                    serial = line.split(":")[1].strip()
                    return serial
    except FileNotFoundError:
        logging.error("File /proc/cpuinfo not found.")
    except Exception as e:
        logging.error(f"An error occurred while retrieving the Raspberry Pi serial number: {e}")
    return None

# logging level 
logging.basicConfig(level=logging.INFO)

# AWS IoT Core endpoint 
aws_endpoint = "YOUR_AWS_IOT_ENDPOINT" 

# Initialize S3 client
s3 = boto3.client('s3', region_name='eu-central-1')
bucket_name = "iot-certificates-bucket"

# Function to dowload the IoT certificates from the S3 bucket if they don't axist inthe IoT device
def download_from_s3(bucket_name, file_key, local_filename):
    try:
        # Download the file from S3
        s3.download_file(bucket_name, file_key, local_filename)
        print(f"File {file_key} from bucket {bucket_name} has been downloaded as {local_filename}.")
    except NoCredentialsError:
        print("Error: AWS credentials not found.")
    except PartialCredentialsError:
        print("Error: Incomplete AWS credentials provided.")
    except ClientError as e:
        if e.response['Error']['Code'] == "404":
            print(f"Error: The object {file_key} does not exist in bucket {bucket_name}.")
        else:
            print(f"Unexpected error: {e}")


# Paths for the certificates
certificate_names = ["raspberry_pi_certificate.pem.crt", "raspberry_pi_private_key.pem.key", "AmazonRootCA1.pem"]
certif_folder = os.path.expanduser("~/.aws_iot_certificates/")

# Download the files only if they do not exist
try:
    for certif in certificate_names:
        certif_path = os.path.join(certif_folder, certif)
        if not os.path.exists(certif_path):
            download_from_s3(bucket_name, f"certificates/{certif}", certif_path)
except Exception  as e: 
    logging.error(f"Error: Could Not Download Certificates from S3: {e}")

def on_connect(client, userdata, flags, rc):
    logging.info(f"Connected to the AWS IoT with result code: {rc}")

    if rc == 0:
        logging.info("Connected to AWS IoT successfully.")
    else:
        logging.error(f"Failed to connect to AWS IoT, return code {rc}")

def on_disconnect(client, userdata, rc):
    if rc != 0:
        logging.warning(f"Unexpected disconnection. Reconnecting... ({rc})")
        client.reconnect()

try:
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.tls_set(ca_certs=f'{certif_folder}/AmazonRootCA1.pem', 
                certfile=f'{certif_folder}/raspberry_pi_certificate.pem.crt', 
                keyfile=f'{certif_folder}/raspberry_pi_private_key.pem.key', 
                tls_version=ssl.PROTOCOL_TLSv1_2, 
                ciphers=None) 

    client.connect(aws_endpoint, 8883, 60)

except Exception as e:
    logging.error(f"Error: Could not connect to AWS IoT: {e}")
    raise

try:
    client.connect(aws_endpoint, 8883, 60)
except Exception as e:
    logging.error(f"An error occurred: {e}")

# Initialize the IMU sensor
sensor = mpu6050(0x69)  

rpi_serial = get_rpi_serial()
if not rpi_serial:
    raise RuntimeError("Unable to retrieve the Raspberry Pi serial number.")

# Set the logging level for the MQTT client
client.enable_logger(logging.getLogger(__name__))

# Start the MQTT client loop
client.loop_start()

data_buffer = []

while True:
    try:
        # Read IMU data
        accel_data = sensor.get_accel_data()
        gyro_data = sensor.get_gyro_data()

        # Accumulate data points in the buffer
        data_buffer.append([accel_data, gyro_data])

        if len(data_buffer) == 128:
            flat_data = []
            
            for data_point in data_buffer:
                accel_data = data_point[0]
                gyro_data = data_point[1]
                flat_data.extend([accel_data['x'], accel_data['y'], accel_data['z'],
                                  gyro_data['x'], gyro_data['y'], gyro_data['z']])

            try:
                # Pack the data buffer into a binary payload
                payload = struct.pack(f'768f', *flat_data)

                # Create JSON mapping
                json_payload = payload.hex() 
                
            except Exception as e:
                logging.error(f"An error occurred while packing the data: {e}")
                continue

            try:

                # Publish the payload to the MQTT topic
                client.publish("raspi/data/{}".format(rpi_serial), json_payload, qos=0, retain=False)
                logging.info("Successfully Published IMU Data!")
                logging.debug(f"IMU data: {json_payload[:100]}...")

            except Exception as e:
                logging.error(f"Error: Could not publish data: {e}")

            # Clear the buffer
            data_buffer.clear()

    except Exception as e:
        logging.error(f"An error occurred: {e}")
