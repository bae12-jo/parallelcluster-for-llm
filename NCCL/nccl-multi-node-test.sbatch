#!/bin/bash
#SBATCH --job-name=nccl-multinode
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=24
#SBATCH --gpus-per-node=8
#SBATCH --exclusive
#SBATCH --time=01:00:00
#SBATCH --output=/fsx/nccl-results/multinode_%j.out
#SBATCH --error=/fsx/nccl-results/multinode_%j.err

# NCCL Multi-Node Performance Test for p5en.48xlarge
# Tests scaling across multiple nodes with EFA networking

set -e

# Environment setup for multi-node
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,GRAPH,ENV,NET
export NCCL_SOCKET_IFNAME=^docker0,lo

# Network-specific settings for 3.2Tbps bandwidth
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1
export NCCL_PROTO=Simple
export NCCL_ALGO=Ring,Tree

# Multi-node optimizations
export NCCL_IB_DISABLE=1
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0
export NCCL_NET_GDR_LEVEL=PIX
export NCCL_CROSS_NIC=0

# H200 optimizations
export NCCL_NVLS_ENABLE=1

# Create results directory
mkdir -p /fsx/nccl-results

# Test parameters
RESULT_FILE="/fsx/nccl-results/multinode_$(date +%Y%m%d_%H%M%S).log"
NODES=$(scontrol show job $SLURM_JOB_ID | grep " NodeList=" | cut -d= -f2)

echo "Starting NCCL Multi-Node test..." | tee $RESULT_FILE
echo "Nodes: $NODES" | tee -a $RESULT_FILE
echo "Total GPUs: $((SLURM_NNODES * 8))" | tee -a $RESULT_FILE
echo "Results will be saved to: $RESULT_FILE"

# Get cluster information
echo "=== Cluster Information ===" >> $RESULT_FILE
echo "Job ID: $SLURM_JOB_ID" >> $RESULT_FILE
echo "Nodes: $NODES" >> $RESULT_FILE
echo "Node count: $SLURM_NNODES" >> $RESULT_FILE
echo "Tasks per node: $SLURM_NTASKS_PER_NODE" >> $RESULT_FILE
echo "Total tasks: $SLURM_NTASKS" >> $RESULT_FILE
echo "Date: $(date)" >> $RESULT_FILE
echo "=========================" >> $RESULT_FILE

# Test network connectivity first
echo "=== Network Connectivity Test ===" >> $RESULT_FILE
srun --ntasks=$SLURM_NTASKS hostname | sort | tee -a $RESULT_FILE
echo "" >> $RESULT_FILE

# Run multi-node AllReduce test
echo "=== Multi-Node NCCL AllReduce Test ===" >> $RESULT_FILE
echo "Testing with $SLURM_NTASKS GPUs across $SLURM_NNODES nodes" >> $RESULT_FILE
echo "========================================" >> $RESULT_FILE

srun --mpi=pmix \
    --ntasks=$SLURM_NTASKS \
    --ntasks-per-node=8 \
    /opt/nccl-tests/all_reduce_perf \
    -b 1M -e 4G -f 2 -g 1 -c 1 -n 50 \
    | tee -a $RESULT_FILE

echo "" >> $RESULT_FILE

# Run multi-node AllGather test
echo "=== Multi-Node NCCL AllGather Test ===" >> $RESULT_FILE
srun --mpi=pmix \
    --ntasks=$SLURM_NTASKS \
    --ntasks-per-node=8 \
    /opt/nccl-tests/all_gather_perf \
    -b 1M -e 2G -f 2 -g 1 -c 1 -n 50 \
    | tee -a $RESULT_FILE

echo "" >> $RESULT_FILE
echo "=== Test Summary ===" >> $RESULT_FILE
echo "Test completed at: $(date)" >> $RESULT_FILE

# Extract key performance metrics
echo "=== Performance Summary ===" | tee -a $RESULT_FILE
echo "Nodes tested: $SLURM_NNODES" | tee -a $RESULT_FILE
echo "Total GPUs: $((SLURM_NNODES * 8))" | tee -a $RESULT_FILE
echo "Expected scaling: Linear with 3.2Tbps networking" | tee -a $RESULT_FILE

# Calculate theoretical peak bandwidth
TOTAL_GPUS=$((SLURM_NNODES * 8))
echo "Theoretical peak (intra-node): $((SLURM_NNODES * 1600)) GB/s" | tee -a $RESULT_FILE
echo "Inter-node bandwidth: 3.2 Tbps = 400 GB/s per node" | tee -a $RESULT_FILE

echo "NCCL Multi-Node test completed successfully!"
echo "Results saved to: $RESULT_FILE"