variable "aws_region" {
  description = "AWS region to launch the ressources."
  default     = "eu-west-2"
}

variable "accountId"{
  description = "Account-ID"
  default     = "566355141541"
}

variable "bucket"{
  description = "Glossaries will be stored on that bucket"
  default     = "bucket-for-glossary"
}