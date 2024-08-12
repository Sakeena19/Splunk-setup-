#!/bin/bash
# Redirects stdout and stderr to a log file for debugging purposes
exec > >(sudo tee -a /var/log/user-data.log) 2>&1
set -e  # Exit immediately if a command exits with a non-zero status

echo "Updating package index"
sudo apt-get update -y  # Updates the package index to ensure the latest versions of packages are installed

echo "Installing Docker"
sudo apt-get install -y docker.io  # Installs Docker

echo "Installing curl and unzip"
sudo apt-get install -y curl unzip  # Installs curl and unzip for downloading files

echo "Installing AWS CLI"
# Downloads the AWS CLI installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip" -o "awscliv2.zip"
unzip awscliv2.zip  # Unzips the downloaded AWS CLI installer
sudo ./aws/install  # Installs AWS CLI

aws --version  # Displays the version of AWS CLI to verify installation

echo "Installing Vault CLI"
# Downloads the Vault CLI installer
curl -o vault.zip "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
unzip vault.zip  # Unzips the downloaded Vault installer
sudo mv vault /usr/local/bin/  # Moves the Vault executable to a directory in the system's PATH
sudo chmod +x /usr/local/bin/vault  # Makes the Vault executable runnable

vault version  # Displays the version of Vault to verify installation

export PATH=$PATH:/usr/local/bin  # Updates the PATH variable to include /usr/local/bin

echo "Starting Docker service"
sudo systemctl start docker  # Starts the Docker service
sudo systemctl enable docker  # Enables Docker to start on boot

sleep 10  # Waits for 10 seconds to ensure Docker service is fully started

export VAULT_ADDR='http://3.234.250.161:8200'  # Sets the Vault server address
VAULT_TOKEN="${vault_token}"  # Retrieves the Vault token from environment variable

# Checks if the Vault token is empty and exits if true
if [ -z "$VAULT_TOKEN" ]; then
    echo "Vault token not found in SSM Parameter Store!"
    exit 1
fi

export VAULT_TOKEN  # Exports the Vault token for use in subsequent commands

# Retrieves the Splunk password from Vault and assigns it to the variable
SPLUNK_PASSWORD=$(vault kv get -field=username kv/secret_splunk)

# Checks if the Splunk password is empty and exits if true
if [ -z "$SPLUNK_PASSWORD" ]; then
    echo "Splunk password not found!"
    exit 1
fi

# Creates a Docker bridge network for communication between containers
sudo docker network create --driver bridge splunknetwork

# Runs the Splunk Enterprise container in the created Docker network
sudo docker run --network splunknetwork --name splunk_container1 --hostname splunk_container1 -p 8001:8000 -e SPLUNK_PASSWORD="$SPLUNK_PASSWORD" -e SPLUNK_START_ARGS="--accept-license" -d splunk/splunk:latest

# Runs the Splunk Universal Forwarder container in the created Docker network
sudo docker run --network splunknetwork --name splunk_container2 --hostname splunk_container2 -e SPLUNK_PASSWORD="$SPLUNK_PASSWORD"  -e SPLUNK_START_ARGS="--accept-license" -e SPLUNK_STANDALONE_URL="splunk_container1" -d splunk/universalforwarder:latest
