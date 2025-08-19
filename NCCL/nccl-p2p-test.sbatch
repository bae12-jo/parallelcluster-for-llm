#!/bin/bash
#SBATCH --job-name=nccl-p2p
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=2
#SBATCH --cpus-per-task=24
#SBATCH --gpus-per-node=8
#SBATCH --exclusive
#SBATCH --time=00:20:00
#SBATCH --output=/fsx/nccl-results/p2p_%j.out
#SBATCH --error=/fsx/nccl-results/p2p_%j.err

# NCCL Point-to-Point Performance Test for p5en.48xlarge
# Tests P2P bandwidth between H200 GPU pairs via NVLink

set -e

# Environment setup
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,GRAPH
export NCCL_SOCKET_IFNAME=^docker0,lo
export NCCL_IB_DISABLE=1
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0

# Performance optimizations for H200 NVLink
export NCCL_NVLS_ENABLE=1
export NCCL_CROSS_NIC=0
export NCCL_NET_GDR_LEVEL=PIX

# Create results directory
mkdir -p /fsx/nccl-results

# Test parameters
RESULT_FILE="/fsx/nccl-results/p2p_$(hostname)_$(date +%Y%m%d_%H%M%S).log"

echo "Starting NCCL Point-to-Point test..." | tee $RESULT_FILE
echo "Results will be saved to: $RESULT_FILE"

# Get GPU topology information
echo "=== GPU Topology Information ===" | tee -a $RESULT_FILE
nvidia-smi topo -m | tee -a $RESULT_FILE
echo "" >> $RESULT_FILE

# Run P2P test between different GPU pairs
echo "=== NCCL Point-to-Point Performance Test ===" >> $RESULT_FILE
echo "Node: $(hostname)" >> $RESULT_FILE
echo "Date: $(date)" >> $RESULT_FILE
echo "GPUs: 8x H200 with NVLink" >> $RESULT_FILE
echo "========================================" >> $RESULT_FILE

# Test GPU 0 <-> GPU 1 (should be NVLink connected)
echo "Testing GPU 0 <-> GPU 1 (NVLink pair)" | tee -a $RESULT_FILE
CUDA_VISIBLE_DEVICES=0,1 mpirun -np 2 \
    --bind-to none \
    --map-by slot \
    --mca pml ob1 \
    --mca btl ^openib \
    /opt/nccl-tests/sendrecv_perf \
    -b 1K -e 2G -f 2 -g 1 -c 1 -n 50 \
    | tee -a $RESULT_FILE

echo "" >> $RESULT_FILE

# Test GPU 0 <-> GPU 4 (cross-NVSwitch)
echo "Testing GPU 0 <-> GPU 4 (cross-NVSwitch)" | tee -a $RESULT_FILE
CUDA_VISIBLE_DEVICES=0,4 mpirun -np 2 \
    --bind-to none \
    --map-by slot \
    --mca pml ob1 \
    --mca btl ^openib \
    /opt/nccl-tests/sendrecv_perf \
    -b 1K -e 2G -f 2 -g 1 -c 1 -n 50 \
    | tee -a $RESULT_FILE

echo "" >> $RESULT_FILE
echo "=== Test Summary ===" >> $RESULT_FILE
echo "Test completed at: $(date)" >> $RESULT_FILE

# Extract key performance metrics
echo "=== Performance Summary ===" | tee -a $RESULT_FILE
echo "Expected NVLink bandwidth: ~900 GB/s per direction" | tee -a $RESULT_FILE
echo "Expected NVSwitch bandwidth: ~900 GB/s per direction" | tee -a $RESULT_FILE

echo "NCCL Point-to-Point test completed successfully!"
echo "Results saved to: $RESULT_FILE"