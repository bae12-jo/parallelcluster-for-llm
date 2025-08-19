#!/bin/bash
#SBATCH --job-name=nccl-broadcast
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=24
#SBATCH --gpus-per-node=8
#SBATCH --exclusive
#SBATCH --time=00:20:00
#SBATCH --output=/fsx/nccl-results/broadcast_%j.out
#SBATCH --error=/fsx/nccl-results/broadcast_%j.err

# NCCL Broadcast Performance Test for p5en.48xlarge
# Tests Broadcast bandwidth across 8x H200 GPUs

set -e

# Environment setup
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,GRAPH
export NCCL_SOCKET_IFNAME=^docker0,lo
export NCCL_IB_DISABLE=1
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0

# Performance optimizations for H200
export NCCL_NVLS_ENABLE=1
export NCCL_CROSS_NIC=0
export NCCL_NET_GDR_LEVEL=PIX
export NCCL_ALGO=Ring,Tree
export NCCL_PROTO=Simple

# Create results directory
mkdir -p /fsx/nccl-results

# Test parameters
RESULT_FILE="/fsx/nccl-results/broadcast_$(hostname)_$(date +%Y%m%d_%H%M%S).log"

echo "Starting NCCL Broadcast test..." | tee $RESULT_FILE
echo "Results will be saved to: $RESULT_FILE"

# Run Broadcast test
echo "=== NCCL Broadcast Performance Test ===" >> $RESULT_FILE
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
    /opt/nccl-tests/broadcast_perf \
    -b 1K -e 2G -f 2 -g 1 -c 1 -n 100 \
    | tee -a $RESULT_FILE

echo "" >> $RESULT_FILE
echo "=== Test Summary ===" >> $RESULT_FILE
echo "Test completed at: $(date)" >> $RESULT_FILE

# Extract key performance metrics
echo "=== Performance Summary ===" | tee -a $RESULT_FILE
grep "8388608" $RESULT_FILE | tail -1 | awk '{print "8MB Broadcast: " $6 " GB/s"}' | tee -a $RESULT_FILE
grep "134217728" $RESULT_FILE | tail -1 | awk '{print "128MB Broadcast: " $6 " GB/s"}' | tee -a $RESULT_FILE
grep "1073741824" $RESULT_FILE | tail -1 | awk '{print "1GB Broadcast: " $6 " GB/s"}' | tee -a $RESULT_FILE

echo "NCCL Broadcast test completed successfully!"
echo "Results saved to: $RESULT_FILE"