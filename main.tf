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
