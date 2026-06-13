#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

pushd terraform-infrastructure > /dev/null
if ! command -v terraform &> /dev/null; then
    echo "Terraform not found. Please ensure it is installed."
    exit 1
fi

echo "Fetching latest IP addresses from Terraform..."
TF_OUTPUT=$(terraform output -json)
popd > /dev/null

FLASK_M7I_IP=$(echo "$TF_OUTPUT" | jq -r '.flask_m7i_ip.value')
FLASK_C7I_IP=$(echo "$TF_OUTPUT" | jq -r '.flask_c7i_ip.value')
FLASK_T3_IP=$(echo "$TF_OUTPUT" | jq -r '.flask_t3_ip.value')
NET_M7I_IP=$(echo "$TF_OUTPUT" | jq -r '.net_m7i_ip.value')
NET_C7I_IP=$(echo "$TF_OUTPUT" | jq -r '.net_c7i_ip.value')
NET_T3_IP=$(echo "$TF_OUTPUT" | jq -r '.net_t3_ip.value')

mkdir -p downloaded_results/flask/m7i
mkdir -p downloaded_results/flask/c7i
mkdir -p downloaded_results/flask/t3
mkdir -p downloaded_results/net/m7i
mkdir -p downloaded_results/net/c7i
mkdir -p downloaded_results/net/t3

echo "Downloading from Flask m7i ($FLASK_M7I_IP)..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/petrescue_oci ubuntu@${FLASK_M7I_IP}:~/Master-Thesis-SoftwareCarbonImpact/petrescue-flask-slice1/results/*.csv downloaded_results/flask/m7i/ || true

echo "Downloading from Flask c7i ($FLASK_C7I_IP)..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/petrescue_oci ubuntu@${FLASK_C7I_IP}:~/Master-Thesis-SoftwareCarbonImpact/petrescue-flask-slice1/results/*.csv downloaded_results/flask/c7i/ || true

echo "Downloading from Flask t3 ($FLASK_T3_IP)..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/petrescue_oci ubuntu@${FLASK_T3_IP}:~/Master-Thesis-SoftwareCarbonImpact/petrescue-flask-slice1/results/*.csv downloaded_results/flask/t3/ || true

echo "Downloading from .NET m7i ($NET_M7I_IP)..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/petrescue_oci ubuntu@${NET_M7I_IP}:~/Master-Thesis-SoftwareCarbonImpact/petrescue-net-slice1/results/*.csv downloaded_results/net/m7i/ || true

echo "Downloading from .NET c7i ($NET_C7I_IP)..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/petrescue_oci ubuntu@${NET_C7I_IP}:~/Master-Thesis-SoftwareCarbonImpact/petrescue-net-slice1/results/*.csv downloaded_results/net/c7i/ || true

echo "Downloading from .NET t3 ($NET_T3_IP)..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/petrescue_oci ubuntu@${NET_T3_IP}:~/Master-Thesis-SoftwareCarbonImpact/petrescue-net-slice1/results/*.csv downloaded_results/net/t3/ || true

echo "All downloads complete!"
