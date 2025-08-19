#!/bin/bash
# source environment-variables.sh
# envsubst < cluster-config.yaml.template > cluster-config.yaml

# parallelcluster-infrastructure.yaml 배포 시 설정한 스택 이름
STACK_NAME="your-parallelcluster-infra-stack"

echo "CloudFormation 스택에서 값들을 가져오는 중..."

# CloudFormation에서 자동으로 가져오는 값들
export AWS_REGION=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].StackStatus' --output text 2>/dev/null && aws configure get region)
export PRIVATE_SUBNET_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==`PrimaryPrivateSubnet`].OutputValue' --output text)
export PUBLIC_SUBNET_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet`].OutputValue' --output text)
export HEAD_NODE_SECURITY_GROUP=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==`HeadNodeSecurityGroup`].OutputValue' --output text)
export COMPUTE_NODE_SECURITY_GROUP=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==`ComputeNodeSecurityGroup`].OutputValue' --output text)
export LOGIN_NODE_SECURITY_GROUP=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==`LoginNodeSecurityGroup`].OutputValue' --output text)
export FSxORootVolumeId=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==`FSxORootVolumeId`].OutputValue' --output text)
export FSxLustreFilesystemId=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==`FSxLustreFilesystemId`].OutputValue' --output text)

# 기본 시스템 설정
export IMDS_SUPPORT="v2.0"
export OS_TYPE="ubuntu2204"
export SCHEDULER="slurm"

# SSH 키 페어 (미리 생성되어 있어야 함)
export KEY_PAIR_NAME="your-ec2-key-pair-name"

# HeadNode 설정
export HEAD_NODE_INSTANCE_TYPE="m5.8xlarge"
export HEAD_NODE_ROOT_VOLUME_SIZE="500"

# LoginNode 설정
export LOGIN_NODE_POOL_NAME="login-pool"
export LOGIN_NODE_COUNT="2"
export LOGIN_NODE_INSTANCE_TYPE="m5.large"
export LOGIN_NODE_OS_TYPE="ubuntu2204"
export LOGIN_NODE_SUBNET_ID="${PUBLIC_SUBNET_ID}"
export LOGIN_NODE_ROOT_VOLUME_SIZE="100"
export LOGIN_NODE_SCRATCH_DIR="/scratch"
export LOGIN_NODE_KEY_PAIR="${KEY_PAIR_NAME}"

# Compute Queue 설정
export QUEUE_NAME="compute-gpu"
export CAPACITY_TYPE="ONDEMAND"
export PLACEMENT_GROUP_ENABLED="true"
export JOB_EXCLUSIVE_ALLOCATION="true"

# ComputeResource 설정
export COMPUTE_RESOURCE_NAME="distributed-ml"
export COMPUTE_INSTANCE_TYPE="p5en.48xlarge"
export COMPUTE_NODE_ROOT_VOLUME_SIZE="200"
export MIN_COUNT="0"
export MAX_COUNT="4"
export EFA_ENABLED="true"

# Slurm 스케줄링 설정
export SCALEDOWN_IDLETIME="60"
export QUEUE_UPDATE_STRATEGY="DRAIN"
export KILL_WAIT="300"
export SLURMD_TIMEOUT="600"
export UNKILLABLE_STEP_TIMEOUT="120"

# NCCL 버전 (keep it up-to-date)
export NCCL_VERSION="v2.27.6-1"
export AWS_OFI_NCCL_VERSION="v1.16.2-aws"

# 모니터링 설정
export DETAILED_MONITORING="true"
export CLOUDWATCH_LOGS_ENABLED="true"
export CLOUDWATCH_DASHBOARDS_ENABLED="true"
export GRAFANA_TAG_VALUE="true"

# 스크립트 URL
export GRAFANA_SCRIPT_URL="https://raw.githubusercontent.com/aws-samples/aws-parallelcluster-monitoring/sc23/post-install.sh"

echo "환경 변수 설정 완료!"
echo "다음 명령으로 설정 파일을 생성하세요:"
echo "envsubst < cluster-config.yaml.template > cluster-config.yaml"