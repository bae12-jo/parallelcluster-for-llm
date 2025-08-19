#!/bin/bash
#SBATCH --job-name=nccl-allreduce
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=24
#SBATCH --gpus-per-node=8
#SBATCH --exclusive
#SBATCH --time=00:30:00
#SBATCH --output=/fsx/nccl-results/allreduce_%j.out
#SBATCH --error=/fsx/nccl-results/allreduce_%j.err

# NCCL AllReduce Performance Test for p5en.48xlarge
# Tests bandwidth and latency across 8x H200 GPUs

set -e

# Environment setup
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,GRAPH,ENV
export NCCL_SOCKET_IFNAME=^docker0,lo
export NCCL_IB_DISABLE=1
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0

# EFA optimizations for multi-node (if applicable)
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export NCCL_ALGO=Ring,Tree
export NCCL_PROTO=Simple

# Performance optimizations for H200
export NCCL_NVLS_ENABLE=1
export NCCL_CROSS_NIC=0
export NCCL_NET_GDR_LEVEL=PIX

# Create results directory
mkdir -p /fsx/nccl-results

# Get node information
echo "=== Node Information ==="
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "CUDA Version: $(nvcc --version | grep release)"
echo "NCCL Version: $(cat /usr/local/cuda/include/nccl.h | grep NCCL_VERSION | head -1)"
echo "GPUs: $(nvidia-smi -L)"
echo "========================"

# Test parameters
RESULT_FILE="/fsx/nccl-results/allreduce_$(hostname)_$(date +%Y%m%d_%H%M%S).log"

echo "Starting NCCL AllReduce test..." | tee $RESULT_FILE
echo "Results will be saved to: $RESULT_FILE"

# Run comprehensive AllReduce test
# Test range: 1KB to 8GB (covers typical ML workloads)
echo "=== NCCL AllReduce Performance Test ===" >> $RESULT_FILE
echo "Node: $(hostname)" >> $RESULT_FILE
echo "Date: $(date)" >> $RESULT_FILE
echo "GPUs: 8x H200" >> $RESULT_FILE
echo "========================================" >> $RESULT_FILE

mpirun -np 8 \
    --bind-to none \
    --map-by slot \
    --mca pml ob1 \
    --mca btl ^openib \
    --mca btl_tcp_if_exclude lo,docker0 \
    /opt/nccl-tests/all_reduce_perf \
    -b 1K -e 8G -f 2 -g 1 -c 1 -n 100 \
    | tee -a $RESULT_FILE

echo "" >> $RESULT_FILE
echo "=== Test Summary ===" >> $RESULT_FILE
echo "Test completed at: $(date)" >> $RESULT_FILE

# Extract key performance metrics
echo "=== Performance Summary ===" | tee -a $RESULT_FILE
grep "8388608" $RESULT_FILE | tail -1 | awk '{print "8MB AllReduce: " $6 " GB/s"}' | tee -a $RESULT_FILE
grep "134217728" $RESULT_FILE | tail -1 | awk '{print "128MB AllReduce: " $6 " GB/s"}' | tee -a $RESULT_FILE
grep "1073741824" $RESULT_FILE | tail -1 | awk '{print "1GB AllReduce: " $6 " GB/s"}' | tee -a $RESULT_FILE

echo "NCCL AllReduce test completed successfully!"
echo "Results saved to: $RESULT_FILE"