terraform {
  cloud {
    organization = "YOUR_ORGANIZATION_NAME"
    workspaces {
      name = "serverless-iot-data-streaming"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

variable "iot_thing_name" {
  default = "raspberry_pi"
}

variable "lambda_function_name" {
  default = "process_imu_data"
}

# S3 bucket to store the IMU data
resource "aws_s3_bucket" "imu_data_bucket" {
  bucket = "processed-imu-data-raspi"
}

# S3 bucket to store certificates
resource "aws_s3_bucket" "certificates_bucket" {
  bucket = "iot-certificates-bucket"
}

# Bucket policy to allow Lambda access
resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_policy_s3_access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*",
      },
      {
        Action = [
          "s3:PutObject",
        ],
        Effect   = "Allow",
        Resource = "arn:aws:s3:::${aws_s3_bucket.imu_data_bucket.bucket}/*",
      },
      {
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListStreams"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:kinesis:eu-central-1:*:stream/imu_data_stream",
      },
    ],
  })
}

resource "aws_iot_thing" "raspberry_pi" {
  name = var.iot_thing_name
}

resource "aws_iot_policy" "raspberry_pi_policy" {
  name   = "raspberry_pi_access_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "iot:Connect",
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = "iot:Publish",
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = "iot:Subscribe",
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = "iot:Receive",
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = "s3:GetObject",
        Resource = [
          "arn:aws:s3:::iot-certif-bucket/*",
        ]
      }
    ]
  })
}

resource "aws_iot_certificate" "raspberry_pi_cert" {
  active = true
}

resource "aws_iot_policy_attachment" "cert_policy_attach" {
  policy = aws_iot_policy.raspberry_pi_policy.name
  target = aws_iot_certificate.raspberry_pi_cert.arn
}

resource "aws_iot_thing_principal_attachment" "thing_cert_attach" {
  thing     = aws_iot_thing.raspberry_pi.name
  principal = aws_iot_certificate.raspberry_pi_cert.arn
}

resource "aws_cloudwatch_log_group" "iot_log_group" {
  name = "/aws/iot/imu_data_rule"
}

resource "aws_cloudwatch_log_stream" "iot_log_stream" {
  name           = "imu_data_stream"
  log_group_name = aws_cloudwatch_log_group.iot_log_group.name
}

# Create Kinesis Data Stream
resource "aws_kinesis_stream" "imu_data_stream" {
  name        = "imu_data_stream"
  shard_count = 1
}

# Create IoT Topic Rule
resource "aws_iot_topic_rule" "imu_data_rule" {
  name        = "imu_data_rule"
  description = "IoT-Kinesis Rule"
  enabled     = true
  sql         = "SELECT * FROM 'raspi/data/+'"
  sql_version = "2016-03-23"
  kinesis {
    role_arn = aws_iam_role.iot_kinesis_role.arn
    stream_name = aws_kinesis_stream.imu_data_stream.name
  }
  cloudwatch_logs {
    log_group_name = aws_cloudwatch_log_group.iot_log_group.name
    role_arn       = aws_iam_role.iot_logging_role.arn
  }
}

data "aws_iam_policy_document" "iot_logging_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      aws_cloudwatch_log_group.iot_log_group.arn,
      "${aws_cloudwatch_log_group.iot_log_group.arn}:*"
    ]
  }
}

resource "aws_iam_role" "iot_logging_role" {
  name               = "iot_logging_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "iot.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "iot_logging_role_policy" {
  name   = "iot_logging_role_policy"
  role   = aws_iam_role.iot_logging_role.id
  policy = data.aws_iam_policy_document.iot_logging_policy.json
}

# Role for IoT to write to Kinesis Data Streams
resource "aws_iam_role" "iot_kinesis_role" {
  name = "iot_kinesis_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "iot.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
  inline_policy {
    name = "iot-kinesis-policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "kinesis:PutRecord"
          ],
          Resource = aws_kinesis_stream.imu_data_stream.arn
        }
      ]
    })
  }
}

# Define the S3 bucket for Lambda deployment package
resource "aws_s3_bucket" "lambda_deployment_bucket" {
  bucket = "lambda-deployment-bucket-terraform"
}


resource "aws_s3_bucket_ownership_controls" "lambda_s3_bucket_ownership" {
  bucket = aws_s3_bucket.lambda_deployment_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "lambda_deployment_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.lambda_s3_bucket_ownership]
  bucket = aws_s3_bucket.lambda_deployment_bucket.id
  acl    = "private"
}

# Ensure the bucket exists before creating the Lambda function
resource "aws_s3_object" "lambda_deployment_package" {
  bucket = aws_s3_bucket.lambda_deployment_bucket.bucket
  key    = "lambda_function.zip"
  source = "lambda_function.zip"  
  etag   = filemd5("lambda_function.zip")  
}

# Lambda function to process the IMU data from Kinesis Data Streams and write to S3
resource "aws_lambda_function" "process_imu_data" {
  s3_bucket        = aws_s3_object.lambda_deployment_package.bucket
  s3_key           = aws_s3_object.lambda_deployment_package.key
  function_name    = "process_imu_data"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  memory_size      = 512
  timeout          = 30
  depends_on       = [aws_s3_object.lambda_deployment_package] 

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.imu_data_bucket.bucket
    }
  }
}

resource "aws_lambda_event_source_mapping" "kinesis_to_lambda" {
  event_source_arn = aws_kinesis_stream.imu_data_stream.arn
  function_name    = aws_lambda_function.process_imu_data.arn
  starting_position = "LATEST"
  batch_size       = 10
  enabled          = true
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Sid    = "",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "s3:PutObject",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:DescribeStream",
      "kinesis:ListStreams"
    ]
    resources = [
      "arn:aws:logs:*:*:*",
      "arn:aws:s3:::${aws_s3_bucket.imu_data_bucket.bucket}/*",
      aws_kinesis_stream.imu_data_stream.arn
    ]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda_policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# Save the certificate to S3 
resource "terraform_data" "upload_certificate" {
  provisioner "local-exec" {
    command = <<EOT
    echo "${aws_iot_certificate.raspberry_pi_cert.certificate_pem}" > /tmp/${aws_iot_thing.raspberry_pi.name}_certificate.pem.crt
    echo "${aws_iot_certificate.raspberry_pi_cert.private_key}" > /tmp/${aws_iot_thing.raspberry_pi.name}_private_key.pem.key
    aws s3 cp /tmp/${aws_iot_thing.raspberry_pi.name}_certificate.pem.crt s3://${aws_s3_bucket.certificates_bucket.bucket}/certificates/${aws_iot_thing.raspberry_pi.name}_certificate.pem.crt
    aws s3 cp /tmp/${aws_iot_thing.raspberry_pi.name}_private_key.pem.key s3://${aws_s3_bucket.certificates_bucket.bucket}/certificates/${aws_iot_thing.raspberry_pi.name}_private_key.pem.key
    EOT
  }
  depends_on = [aws_iot_certificate.raspberry_pi_cert, aws_s3_bucket.certificates_bucket]
}
