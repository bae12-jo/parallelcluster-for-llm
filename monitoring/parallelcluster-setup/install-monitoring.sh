#!/bin/bash -i
#
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
#

#source the AWS ParallelCluster profile
. /etc/parallelcluster/cfnconfig

# Detect OS and install Docker accordingly
OS=$(. /etc/os-release; echo $NAME)
echo "Detected OS: ${OS}"

if [ "${OS}" = "Ubuntu" ]; then
    # Ubuntu installation
    apt-get update
    apt-get install -y docker.io cloud-utils
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker $cfn_cluster_user
    
    # Install Docker Compose v2
    apt-get install -y docker-compose-plugin
    # Create symlink for backward compatibility
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    
elif [ "${OS}" = "Amazon Linux" ] || [ "${OS}" = "CentOS Linux" ] || [ "${OS}" = "Red Hat Enterprise Linux" ]; then
    # Amazon Linux/RHEL installation
    yum -y install docker
    service docker start
    chkconfig docker on
    usermod -a -G docker $cfn_cluster_user
    
    # Install Docker Compose v2
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    echo "Unsupported OS: ${OS}"
    exit 1
fi

monitoring_dir_name=aws-parallelcluster-monitoring
monitoring_home="/home/${cfn_cluster_user}/${monitoring_dir_name}"

echo "$> variable monitoring_dir_name -> ${monitoring_dir_name}"
echo "$> variable monitoring_home -> ${monitoring_home}"


case "${cfn_node_type}" in
	HeadNode | MasterServer)

		#cfn_efs=$(cat /etc/chef/dna.json | grep \"cfn_efs\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		#cfn_cluster_cw_logging_enabled=$(cat /etc/chef/dna.json | grep \"cfn_cluster_cw_logging_enabled\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cfn_fsx_fs_id=$(cat /etc/chef/dna.json | grep \"cfn_fsx_fs_id\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		# Get instance ID using appropriate command based on OS
		if [ "${OS}" = "Ubuntu" ]; then
			master_instance_id=$(ec2metadata --instance-id)
		else
			master_instance_id=$(ec2-metadata -i | awk '{print $2}')
		fi
		cfn_max_queue_size=$(aws cloudformation describe-stacks --stack-name $stack_name --region $cfn_region | jq -r '.Stacks[0].Parameters | map(select(.ParameterKey == "MaxSize"))[0].ParameterValue')
		s3_bucket=$(echo $cfn_postinstall | sed "s/s3:\/\///g;s/\/.*//")
		cluster_s3_bucket=$(cat /etc/chef/dna.json | grep \"cluster_s3_bucket\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cluster_config_s3_key=$(cat /etc/chef/dna.json | grep \"cluster_config_s3_key\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cluster_config_version=$(cat /etc/chef/dna.json | grep \"cluster_config_version\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		log_group_names="\/aws\/parallelcluster\/$(echo ${stack_name} | cut -d "-" -f2-)"

		aws s3api get-object --bucket $cluster_s3_bucket --key $cluster_config_s3_key --region $cfn_region --version-id $cluster_config_version ${monitoring_home}/parallelcluster-setup/cluster-config.json

		# Install Go based on OS
		if [ "${OS}" = "Ubuntu" ]; then
			apt-get install -y golang-go
		else
			yum -y install golang-bin
		fi

		chown $cfn_cluster_user:$cfn_cluster_user -R /home/$cfn_cluster_user
		chmod +x ${monitoring_home}/custom-metrics/*

		cp -rp ${monitoring_home}/custom-metrics/* /usr/local/bin/
		mv ${monitoring_home}/prometheus-slurm-exporter/slurm_exporter.service /etc/systemd/system/

	 	(crontab -l -u $cfn_cluster_user; echo "*/1 * * * * /usr/local/bin/1m-cost-metrics.sh") | crontab -u $cfn_cluster_user -
		(crontab -l -u $cfn_cluster_user; echo "*/60 * * * * /usr/local/bin/1h-cost-metrics.sh") | crontab -u $cfn_cluster_user -


		# replace tokens
		sed -i "s/_S3_BUCKET_/${s3_bucket}/g"               	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__FSX_ID__/${cfn_fsx_fs_id}/g"            	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__AWS_REGION__/${cfn_region}/g"           	${monitoring_home}/grafana/dashboards/ParallelCluster.json

		sed -i "s/__AWS_REGION__/${cfn_region}/g"           	${monitoring_home}/grafana/dashboards/logs.json
		sed -i "s/__LOG_GROUP__NAMES__/${log_group_names}/g"    ${monitoring_home}/grafana/dashboards/logs.json

		sed -i "s/__Application__/${stack_name}/g"          	${monitoring_home}/prometheus/prometheus.yml
		sed -i "s/__AWS_REGION__/${cfn_region}/g"          		${monitoring_home}/prometheus/prometheus.yml

		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/master-node-details.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/compute-node-list.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/compute-node-details.json

		sed -i "s/__MONITORING_DIR__/${monitoring_dir_name}/g"  ${monitoring_home}/docker-compose/docker-compose.master.yml

		#Generate selfsigned certificate for Nginx over ssl
		nginx_dir="${monitoring_home}/nginx"
		nginx_ssl_dir="${nginx_dir}/ssl"
		mkdir -p ${nginx_ssl_dir}
		# Get public hostname using appropriate command based on OS
		if [ "${OS}" = "Ubuntu" ]; then
			public_hostname=$(ec2metadata --public-hostname)
		else
			public_hostname=$(ec2-metadata -p | awk '{print $2}')
		fi
		echo -e "\nDNS.1=${public_hostname}" >> "${nginx_dir}/openssl.cnf"
		openssl req -new -x509 -nodes -newkey rsa:4096 -days 3650 -keyout "${nginx_ssl_dir}/nginx.key" -out "${nginx_ssl_dir}/nginx.crt" -config "${nginx_dir}/openssl.cnf"

		#give $cfn_cluster_user ownership
		chown -R $cfn_cluster_user:$cfn_cluster_user "${nginx_ssl_dir}/nginx.key"
		chown -R $cfn_cluster_user:$cfn_cluster_user "${nginx_ssl_dir}/nginx.crt"

		/usr/local/bin/docker-compose --env-file /etc/parallelcluster/cfnconfig -f ${monitoring_home}/docker-compose/docker-compose.master.yml -p monitoring-master up -d

		# Download and build prometheus-slurm-exporter
		##### Plese note this software package is under GPLv3 License #####
		# More info here: https://github.com/vpenso/prometheus-slurm-exporter/blob/master/LICENSE
		cd ${monitoring_home}
		git clone https://github.com/vpenso/prometheus-slurm-exporter.git
		# the export and git config statements below for compatibility on Ubuntu 22.x
		export HOME=/root
		git config --global --add safe.directory ${monitoring_home}/prometheus-slurm-exporter
		sed -i 's/NodeList,AllocMem,Memory,CPUsState,StateLong/NodeList: ,AllocMem: ,Memory: ,CPUsState: ,StateLong:/' prometheus-slurm-exporter/node.go
		cd prometheus-slurm-exporter
		GOPATH=/root/go-modules-cache HOME=/root go mod download
		GOPATH=/root/go-modules-cache HOME=/root go build
		mv ${monitoring_home}/prometheus-slurm-exporter/prometheus-slurm-exporter /usr/bin/prometheus-slurm-exporter

		systemctl daemon-reload
		systemctl enable slurm_exporter
		systemctl start slurm_exporter
	;;

	ComputeFleet)
		# Get instance type using appropriate command based on OS
		if [ "${OS}" = "Ubuntu" ]; then
			compute_instance_type=$(ec2metadata --instance-type)
		else
			compute_instance_type=$(ec2-metadata -t | awk '{print $2}')
		fi
		
		# Updated GPU instance detection including p5en
		gpu_instances="[pg][2-9].*\.[0-9]*[x]*large"
		echo "$> Compute Instances Type EC2 -> ${compute_instance_type}"
		echo "$> GPUS Instances EC2 -> ${gpu_instances}"
		
		# Check for GPU instances including p5en specifically
		if [[ $compute_instance_type =~ ^p5en\. ]] || [[ $compute_instance_type =~ $gpu_instances ]]; then
			echo "GPU instance detected: $compute_instance_type"
			
			if [ "${OS}" = "Ubuntu" ]; then
				# Ubuntu NVIDIA Docker setup
				distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
				curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
				curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
					sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
					tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
				apt-get update
				apt-get install -y nvidia-container-toolkit
				systemctl restart docker
			else
				# Amazon Linux/RHEL NVIDIA Docker setup
				distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
				curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | tee /etc/yum.repos.d/nvidia-docker.repo
				yum -y clean expire-cache
				yum -y install nvidia-docker2
				systemctl restart docker
			fi
			
			/usr/local/bin/docker-compose -f /home/${cfn_cluster_user}/${monitoring_dir_name}/docker-compose/docker-compose.compute.gpu.yml -p monitoring-compute up -d
        else
			/usr/local/bin/docker-compose -f /home/${cfn_cluster_user}/${monitoring_dir_name}/docker-compose/docker-compose.compute.yml -p monitoring-compute up -d
        fi
	;;
esac
