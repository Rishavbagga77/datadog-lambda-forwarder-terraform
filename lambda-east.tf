terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-gov-east-1"
}

variable "invoke" {
  type = list(string)
  default = ["arn:aws-us-gov:s3:::lifebit-logging-govcloud"]
  #default = ["arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026597159496/vpcflowlogs/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026592988471/vpcflowlogs/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026589913916/vpcflowlogs/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026557756475/vpcflowlogs/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026536877604/GuardDuty/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026553734564/GuardDuty/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026557756475/GuardDuty/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026592988471/GuardDuty/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026597159496/GuardDuty/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026592988471/network-firewall/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026589913916/network-firewall/", "arn:aws-us-gov:s3:::lifebit-logging-govcloud/AWSLogs/026557756475/network-firewall/"]
}

#to collect aws region and account_id to create arns
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Store Datadog API key in AWS Secrets Manager
variable "secret_arn" {
  type        = string
  description = "Please enter aws secret arn of datadog api key"
}

#creating Datadog forwarder Lambda
resource "aws_cloudformation_stack" "datadog_forwarder" {
  name         = "datadog-forwarder-tf"
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]
  parameters   = {
    DdApiKeySecretArn  = var.secret_arn,
    DdSite             = "ddog-gov.com",
    FunctionName       = "datadog-forwarder-tf-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  }
  template_url = "https://datadog-cloudformation-template.s3.amazonaws.com/aws/forwarder/latest.yaml"
}

#Adding invokes to Datadog Lambda
resource "aws_lambda_permission" "allow_bucket" {
  for_each = toset(var.invoke)
  action        = "lambda:InvokeFunction"
  function_name = join(":", ["arn:aws-us-gov","lambda",data.aws_region.current.name,data.aws_caller_identity.current.account_id,"function","datadog-forwarder-tf-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"])
  principal     = "s3.amazonaws.com"
  source_arn    = each.value
  depends_on = [
    aws_cloudformation_stack.datadog_forwarder
  ]
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "lifebit-logging-govcloud"
  lambda_function {
    lambda_function_arn = join(":", ["arn:aws-us-gov","lambda",data.aws_region.current.name,data.aws_caller_identity.current.account_id,"function","datadog-forwarder-tf-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"])
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "AWSLogs/"
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}
