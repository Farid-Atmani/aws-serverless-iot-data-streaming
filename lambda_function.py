import os
import json
import boto3
import base64
import struct
import pandas as pd
from datetime import datetime

s3 = boto3.client('s3')
bucket_name = os.environ['S3_BUCKET']

def lambda_handler(event, context):
    try:
        payload = base64.b64decode(event['Records'][0]['kinesis']['data']).decode('utf-8')
        payload = bytes.fromhex(payload)
            
        rpi_serial = event['Records'][0]['kinesis']['partitionKey'].split('/')[-1]

        # Extract the serial number and IMU data from the binary payload
        flat_data = struct.unpack(f'768f', payload)

        # Create a unique file name
        file_name = f"{rpi_serial}/{rpi_serial}_imu_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pkl"

        # Ensure the directory exists
        local_directory = os.path.join("/tmp", rpi_serial)
        os.makedirs(local_directory, exist_ok=True)

        local_file_path = os.path.join(local_directory, f"{rpi_serial}_imu_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pkl")

        # Initialize lists to store accelerometer and gyroscope data
        x_accel, y_accel, z_accel = [], [], []
        x_gyro, y_gyro, z_gyro = [], [], []

        for i in range(128):
            accel_data = {
                'x': flat_data[i * 6],
                'y': flat_data[i * 6 + 1],
                'z': flat_data[i * 6 + 2]
            }
            gyro_data = {
                'x': flat_data[i * 6 + 3],
                'y': flat_data[i * 6 + 4],
                'z': flat_data[i * 6 + 5]
            }
            x_accel.append(accel_data['x'])
            y_accel.append(accel_data['y'])
            z_accel.append(accel_data['z'])
            x_gyro.append(gyro_data['x'])
            y_gyro.append(gyro_data['y'])
            z_gyro.append(gyro_data['z'])

        # Create DataFrame
        df = pd.DataFrame({
            'x_accel': x_accel,
            'y_accel': y_accel,
            'z_accel': z_accel,
            'x_gyro': x_gyro,
            'y_gyro': y_gyro,
            'z_gyro': z_gyro
        })

        # Save the data to a temporary file and upload it to S3
        df.to_pickle(local_file_path)
        
        # Upload the pickle file to an S3 bucket
        s3.upload_file(local_file_path, bucket_name, file_name)

        return {
            'statusCode': 200,
            'body': json.dumps('Data saved to S3')
        }
        
    except Exception as e:
        print(f"An error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"An error occurred: {str(e)}")
        }
