provider "aws" {
  profile = "default"
  region  = "us-west-2"
}

resource "aws_iot_policy" "iot_policy" {
  name = "aws-reinvent-2024"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:*"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role" "iot_role" {
  name = "aws-reinvent-2024"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "iot_registration" {
  role       = aws_iam_role.iot_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTThingsRegistration"
}
resource "aws_iam_role_policy_attachment" "iot_logging" {
  role       = aws_iam_role.iot_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTLogging"
}
resource "aws_iam_role_policy_attachment" "iot_actions" {
  role       = aws_iam_role.iot_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTRuleActions"
}

data "aws_iot_registration_code" "reinvent_code" {}

resource "tls_cert_request" "verification" {
  private_key_pem = tls_private_key.verification.private_key_pem
  subject {
    common_name = data.aws_iot_registration_code.reinvent_code.registration_code
  }
}

resource "tls_private_key" "verification" {
  algorithm = "RSA"
}

resource "tls_locally_signed_cert" "online_device_ca_verification" {
  cert_request_pem      = tls_cert_request.verification.cert_request_pem
  ca_private_key_pem    = file("../pki/online-key")
  ca_cert_pem           = file("../pki/online-crt")
  validity_period_hours = 12
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

// TODO - how to get people the online-crt - I grabbed this from our backend
resource "aws_iot_ca_certificate" "online_device_ca" {
  active                       = true
  ca_certificate_pem           = file("../pki/online-crt")
  verification_certificate_pem = tls_locally_signed_cert.online_device_ca_verification.cert_pem
  allow_auto_registration      = true

  registration_config {
    role_arn = aws_iam_role.iot_role.arn
    template_body = jsonencode({
      Parameters = {
        "AWS::IoT::Certificate::Id"           = { Type = "String" }
        "AWS::IoT::Certificate::CommonName"   = { Type = "String" }
        "AWS::IoT::Certificate::SerialNumber" = { Type = "String" }
      }
      Resources = {
        thing = {
          Type = "AWS::IoT::Thing"
          Properties = {
            ThingName        = { Ref = "AWS::IoT::Certificate::CommonName" }
            AttributePayload = { SerialNumber = { Ref = "AWS::IoT::Certificate::SerialNumber" } }
          }
        }
        certificate = {
          Type = "AWS::IoT::Certificate"
          Properties = {
            CertificateId = { Ref = "AWS::IoT::Certificate::Id" }
            Status        = "ACTIVE"
          }
        }
        policy = {
          Type       = "AWS::IoT::Policy"
          Properties = { PolicyName = aws_iot_policy.iot_policy.name }
        }
      }
    })
  }
}

resource "aws_timestreamwrite_database" "db" {
  database_name = "aws-reinvent-2024"
}

resource "aws_timestreamwrite_table" "iot_metrics" {
  database_name = aws_timestreamwrite_database.db.database_name
  table_name    = "iot-metrics"
}

resource "aws_timestreamwrite_table" "object_detection" {
  database_name = aws_timestreamwrite_database.db.database_name
  table_name    = "iot-object-detection"
}

resource "aws_cloudwatch_log_group" "timestream_errors" {
  name              = "aws-reinvent-2024-timestream-errors"
  retention_in_days = 3
}

resource "aws_iot_topic_rule" "rule" {
  name        = "aws_reinvent_metrics"
  enabled     = true
  sql         = "SELECT * FROM 'iot/host-metrics'"
  sql_version = "2016-03-23"

  timestream {
    role_arn      = aws_iam_role.iot_role.arn
    database_name = aws_timestreamwrite_database.db.database_name
    table_name    = aws_timestreamwrite_table.iot_metrics.table_name

    dimension {
      name  = "device_uuid"
      value = "$${device_uuid}"
    }
  }

  error_action {
    cloudwatch_logs {
      role_arn       = aws_iam_role.iot_role.arn
      log_group_name = aws_cloudwatch_log_group.timestream_errors.name
    }
  }
}

resource "aws_iot_topic_rule" "detection_rule" {
  name        = "aws_reinvent_detection"
  enabled     = true
  sql         = "SELECT * FROM 'iot/object-detection'"
  sql_version = "2016-03-23"

  timestream {
    role_arn      = aws_iam_role.iot_role.arn
    database_name = aws_timestreamwrite_database.db.database_name
    table_name    = aws_timestreamwrite_table.object_detection.table_name

    dimension {
      name  = "device_uuid"
      value = "$${device_uuid}"
    }
  }

  error_action {
    cloudwatch_logs {
      role_arn       = aws_iam_role.iot_role.arn
      log_group_name = aws_cloudwatch_log_group.timestream_errors.name
    }
  }
}

resource "aws_iam_role" "grafana_role" {
  name = "aws-reinvent-2024-grafana"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "grafana_profile" {
  name = "aws-reinvent-2024-grafana"
  role = aws_iam_role.grafana_role.name
}

resource "aws_iam_policy_attachment" "grafana_timestream" {
  name       = "aws-reinvent-2024-grafana-timestream"
  roles      = [aws_iam_role.grafana_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonTimestreamReadOnlyAccess"
}
resource "aws_iam_policy_attachment" "grafana_mqtt" {
  name       = "aws-reinvent-2024-grafana-timestream"
  roles      = [aws_iam_role.grafana_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AWSIoTDataAccess"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "grafana" {
  name = "aws-reinvent-2024-grafana"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "grafana" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = "andy qc yubi"
  user_data     = file("setup-instance.sh")

  tags = {
    Name = "aws-reinvent-2024-grafana"
  }

  iam_instance_profile = aws_iam_instance_profile.grafana_profile.name
  security_groups      = [aws_security_group.grafana.name]
}

/* Grafana query:
SELECT
    device_uuid,
    CREATE_TIME_SERIES(time, measure_value::bigint) as memory_free_percent
FROM $__database.$__table
WHERE $__timeFilter
    AND measure_name = '$__measure'
GROUP BY
    device_uuid

SELECT
    device_uuid,
    CREATE_TIME_SERIES(time, measure_value::bigint) as $__measure
FROM $__database.$__table
WHERE $__timeFilter
    AND measure_name = '$__measure'
GROUP BY
    device_uuid
*/
