# Configure the AWS provider to interact with AWS resources in the us-east-1 region
provider "aws" {
  region = "us-east-1"
}

# Configure the Vault provider to interact with a Vault server for secret management
provider "vault" {
  address = "http://18.206.114.175:8200"  # Vault server address
  skip_child_token = true  # Avoid using child tokens for authentication

  # Authenticate to Vault using AppRole
  auth_login {
    path = "auth/approle/login"  # Authentication path in Vault
    parameters = {
      role_id   = "5c9ea720-e927-950a-c0a7-0692de55f012"  # Role ID for AppRole authentication
      secret_id = "7e35f7ff-9025-ed98-0ebd-e843bc258822"  # Secret ID for AppRole authentication
    }
  }
}

# Retrieve the Vault token stored in AWS SSM Parameter Store
data "aws_ssm_parameter" "vault_token" {
  name            = "VAULT_TOKEN"  # Name of the parameter in SSM
  with_decryption = true  # Decrypt the parameter value
}

# Fetch a secret from Vault (v2 KV secrets engine)
data "vault_kv_secret_v2" "example" {
  mount = "kv"  # KV mount point in Vault
  name  = "secret_splunk"  # Name of the secret to retrieve
}

# Create an AWS key pair for SSH access to the EC2 instance
resource "aws_key_pair" "TF_key" {
  key_name   = "TF-key"  # Name of the key pair in AWS
  public_key = tls_private_key.rsa.public_key_openssh  # Use the generated RSA public key
}

# Save the private key to a local file for later use
resource "local_file" "TF-key" {
  content  = tls_private_key.rsa.private_key_pem  # The private key content
  filename = "tfkey"  # File name to save the private key
}

# Generate an RSA private key with 4096 bits
resource "tls_private_key" "rsa" {
  algorithm = "RSA"  # Specify the algorithm as RSA
  rsa_bits  = 4096  # Size of the RSA key
}

# Create a security group to allow SSH and HTTP traffic to the Splunk instance
resource "aws_security_group" "splunk_sg" {
  name        = "splunk_sg_new"  # Name of the security group
  description = "Allow SSH and HTTP traffic"  # Description of the security group

  ingress {  # Inbound rule to allow SSH traffic
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH access from anywhere
  }

  ingress {  # Inbound rule to allow HTTP traffic on port 8000 (for Splunk)
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP access from anywhere
  }

  egress {  # Outbound rule to allow all traffic
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all protocols
    cidr_blocks = ["0.0.0.0/0"]  # Allow outbound traffic to anywhere
  }
}

# Provision an AWS EC2 instance to run Splunk
resource "aws_instance" "splunk_instance" {
  ami             = "ami-04a81a99f5ec58529"  # AMI ID for the EC2 instance (Ubuntu 20.04 LTS)
  instance_type   = "t3.medium"  # Instance type
  security_groups = [aws_security_group.splunk_sg.name]  # Assign the previously created security group
  key_name        = aws_key_pair.TF_key.key_name  # Use the created key pair for SSH access
  user_data       = templatefile("./user-data.sh.tpl", {  # User data script to configure the instance
    vault_token     = data.aws_ssm_parameter.vault_token.value,  # Pass the Vault token to the script
    AWS_CLI_VERSION = "2.9.20",  # Specify the version of AWS CLI to install
    VAULT_VERSION   = "1.13.3"  # Specify the version of Vault CLI to install
  })

  root_block_device {  # Configure the root volume
    volume_size = 50  # Set the size of the root volume to 50 GB
  }

  tags = {  # Tag the instance for easy identification
    Name        = "SplunkInstance"
    VAULT_TOKEN = data.aws_ssm_parameter.vault_token.value  # Include the Vault token as a tag
  }
}