#!/bin/bash
#
# AWS ParallelCluster Monitoring Installation Script for LoginNode
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Usage: ./post-install-loginnode.sh [version]

# Load AWS ParallelCluster environment variables
. /etc/parallelcluster/cfnconfig

monitoring_dir_name=aws-parallelcluster-monitoring
monitoring_tarball="${monitoring_dir_name}.tar.gz"

# GitHub repository URL (will contain all current workspace files)
monitoring_repo_url="https://github.com/bae12-jo/parallelcluster-for-llm"
monitoring_archive_url="${monitoring_repo_url}/archive/refs/heads/main.tar.gz"
setup_command="install-monitoring.sh"
monitoring_home="/home/${cfn_cluster_user}/${monitoring_dir_name}"
setup_command_path="${monitoring_home}/parallelcluster-setup"

echo "Installing ParallelCluster Monitoring on ${cfn_node_type}"
echo "Repository: ${monitoring_repo_url}"
echo "User: ${cfn_cluster_user}"

case ${cfn_node_type} in
    HeadNode | MasterServer | LoginNode)
        echo "Downloading monitoring package from: ${monitoring_archive_url}"
        
        # Create monitoring directory
        mkdir -p ${monitoring_home}
        
        # Download and extract monitoring package from GitHub
        if wget ${monitoring_archive_url} -O ${monitoring_tarball}; then
            echo "Successfully downloaded monitoring package"
            # Extract and move monitoring folder contents to the target directory
            tar xzf ${monitoring_tarball}
            extracted_dir=$(tar tzf ${monitoring_tarball} | head -1 | cut -f1 -d"/")
            
            # Copy monitoring folder contents to target location
            if [[ -d "${extracted_dir}/monitoring" ]]; then
                cp -r ${extracted_dir}/monitoring/* ${monitoring_home}/
                echo "Monitoring files extracted successfully"
                
                # Copy NCCL tests to shared storage for compute nodes
                if [[ -d "${extracted_dir}/nccl" ]]; then
                    nccl_shared="/fsx/nccl-tests"
                    mkdir -p ${nccl_shared}
                    cp -r ${extracted_dir}/nccl/* ${nccl_shared}/
                    chmod +x ${nccl_shared}/*.sh
                    chown -R ${cfn_cluster_user}:${cfn_cluster_user} ${nccl_shared}
                    echo "NCCL test scripts copied to shared storage: ${nccl_shared}"
                fi
            else
                echo "Error: monitoring folder not found in archive"
                exit 1
            fi
            
            # Cleanup
            rm -f ${monitoring_tarball}
            rm -rf ${extracted_dir}
        else
            echo "Failed to download monitoring package from GitHub"
            echo "Please check if the repository is accessible: ${monitoring_repo_url}"
            exit 1
        fi
        
        # Set ownership for monitoring files
        chown -R ${cfn_cluster_user}:${cfn_cluster_user} ${monitoring_home}
        
        # NCCL files are already handled above in shared storage
        
        # Install monitoring stack
        if [ -f "${setup_command_path}/${setup_command}" ]; then
            echo "Found installation script: ${setup_command_path}/${setup_command}"
        else
            echo "Installation script not found!"
            exit 1
        fi
    ;;
    ComputeFleet)
        echo "Compute node - no monitoring installation needed"
        exit 0
    ;;
    *)
        echo "Unknown node type: ${cfn_node_type}"
        exit 1
    ;;
esac

# Detect OS and adjust installation accordingly
OS=$(. /etc/os-release; echo $NAME)
echo "Detected OS: ${OS}"

if [ "${OS}" = "Ubuntu" ]; then
    echo "Configuring for Ubuntu..."
    
    # Stop and disable Apache if running (conflicts with Grafana)
    if systemctl is-active --quiet apache2; then
        systemctl stop apache2
        systemctl disable apache2
        echo "Stopped conflicting Apache service"
    fi
    
    # Update package manager
    apt-get update
    apt-get install -y cloud-utils
    
    # Create modified setup script for Ubuntu
    sed \
        -e "s/yum -y install docker/apt-get install docker.io -y/g" \
        -e "s/yum -y install golang-bin/apt-get install golang-go -y/g" \
        -e "s/ec2-metadata -i | awk '{print \$2}'/ec2metadata --instance-id/g" \
        -e "s/ec2-metadata -p | awk '{print \$2}'/ec2metadata --public-hostname/g" \
        -e "s/ec2-metadata -t | awk '{print \$2}'/ec2metadata --instance-type/g" \
        "${setup_command_path}/${setup_command}" \
        > "${setup_command_path}/ubuntu-${setup_command}"
    
    chmod +x "${setup_command_path}/ubuntu-${setup_command}"
    
    echo "Running Ubuntu-specific monitoring setup..."
    bash -x "${setup_command_path}/ubuntu-${setup_command}" | tee /tmp/monitoring-setup.log 2>&1
    setup_exit_code=$?
    
elif [ "${OS}" = "Amazon Linux" ] || [ "${OS}" = "CentOS Linux" ] || [ "${OS}" = "Red Hat Enterprise Linux" ]; then
    echo "Configuring for ${OS}..."
    
    # Install ec2-metadata if not available
    if ! command -v ec2-metadata &> /dev/null; then
        yum install -y ec2-utils
    fi
    
    echo "Running standard monitoring setup..."
    bash -x "${setup_command_path}/${setup_command}" | tee /tmp/monitoring-setup.log 2>&1
    setup_exit_code=$?
    
else
    echo "Unsupported OS: ${OS}"
    exit 1
fi

# Check installation result
if [ $setup_exit_code -eq 0 ]; then
    echo "Monitoring installation completed successfully!"
    
    # Additional LoginNode specific configuration
    if [ "${cfn_node_type}" = "LoginNode" ]; then
        echo "Configuring LoginNode-specific settings..."
        
        # Wait for Docker containers to be ready
        sleep 30
        
        # Check if Grafana container is running
        if docker ps | grep -q grafana; then
            echo "Grafana container is running"
            
            # Output connection information
            instance_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
            if [ -n "$instance_ip" ]; then
                echo "=========================================="
                echo "ParallelCluster Monitoring Dashboard Access:"
                echo "HTTPS URL: https://${instance_ip}/grafana/"
                echo "HTTP URL:  http://${instance_ip}/grafana/"
                echo ""
                echo "Direct Grafana Access:"
                echo "URL: http://${instance_ip}:3000"
                echo ""
                echo "Default Grafana credentials:"
                echo "  Username: admin"
                echo "  Password: Grafana4PC!"
                echo ""
                echo "Prometheus: https://${instance_ip}/prometheus/"
                echo "Pushgateway: https://${instance_ip}/pushgateway/"
                echo ""
                if [[ -d "/fsx/nccl-tests" ]]; then
                    echo "NCCL Test Scripts (for compute nodes):"
                    echo "  Location: /fsx/nccl-tests/"
                    echo "  Install: ssh to compute node, run /fsx/nccl-tests/install-nccl-tests.sh"
                    echo "  Run tests: sbatch /fsx/nccl-tests/nccl-*.sbatch"
                fi
                echo "=========================================="
            else
                echo "Could not retrieve public IP address"
            fi
        else
            echo "Warning: Grafana container is not running"
        fi
        
        # Configure firewall if ufw is available (Ubuntu)
        if command -v ufw &> /dev/null; then
            echo "Configuring Ubuntu firewall for monitoring ports..."
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw allow 3000/tcp
            echo "Firewall configured for monitoring access"
        fi
    fi
    
    echo "Installation log available at: /tmp/monitoring-setup.log"
else
    echo "Monitoring installation failed with exit code: $setup_exit_code"
    echo "Check /tmp/monitoring-setup.log for details"
    exit $setup_exit_code
fi

exit 0