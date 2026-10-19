terraform {

  backend "s3" {

    bucket = "sentinelpay-terraform-state-5f5321b4"

    key = "environments/dev/terraform.tfstate"

    region = "eu-west-1"

    encrypt = true

    dynamodb_table = "sentinelpay-terraform-locks"
  }
}