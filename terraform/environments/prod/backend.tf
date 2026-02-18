terraform {
    backend "s3" {
        bucket = "cipherpol-terraform-state-758620460011"
        key = "prod/terraform.tfstate"
        region = "us-east-1"
        dynamodb_table = "terraform-state-lock"
        encrypt = true
    }
}