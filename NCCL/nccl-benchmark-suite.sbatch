#!/bin/bash
#SBATCH --job-name=nccl-benchmark-suite
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=24
#SBATCH --gpus-per-node=8
#SBATCH --exclusive
#SBATCH --time=02:00:00
#SBATCH --output=/fsx/nccl-results/benchmark-suite_%j.out
#SBATCH --error=/fsx/nccl-results/benchmark-suite_%j.err

# NCCL Comprehensive Benchmark Suite for p5en.48xlarge
# Runs all NCCL tests and generates performance report

set -e

# Environment setup
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export NCCL_DEBUG=WARN  # Reduce verbosity for comprehensive test
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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="/fsx/nccl-results/benchmark-suite_$TIMESTAMP"
mkdir -p $RESULT_DIR

echo "Starting NCCL Comprehensive Benchmark Suite..."
echo "Results directory: $RESULT_DIR"

# System information
echo "=== System Information ===" | tee $RESULT_DIR/system-info.log
echo "Node: $(hostname)" | tee -a $RESULT_DIR/system-info.log
echo "Date: $(date)" | tee -a $RESULT_DIR/system-info.log
echo "CUDA Version: $(nvcc --version | grep release)" | tee -a $RESULT_DIR/system-info.log
echo "Driver Version: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)" | tee -a $RESULT_DIR/system-info.log
echo "GPU Count: $(nvidia-smi -L | wc -l)" | tee -a $RESULT_DIR/system-info.log
echo "GPU Model: $(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1)" | tee -a $RESULT_DIR/system-info.log
echo "GPU Memory: $(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1) MB per GPU" | tee -a $RESULT_DIR/system-info.log
echo "" | tee -a $RESULT_DIR/system-info.log

# GPU topology
echo "=== GPU Topology ===" | tee -a $RESULT_DIR/system-info.log
nvidia-smi topo -m | tee -a $RESULT_DIR/system-info.log
echo "" | tee -a $RESULT_DIR/system-info.log

# MPI setup
MPI_OPTS="--bind-to none --map-by slot --mca pml ob1 --mca btl ^openib --mca btl_tcp_if_exclude lo,docker0"

echo "Running NCCL benchmark suite..."

# 1. AllReduce Test
echo "1/6 Running AllReduce test..." | tee -a $RESULT_DIR/progress.log
mpirun -np 8 $MPI_OPTS /opt/nccl-tests/all_reduce_perf \
    -b 1K -e 8G -f 2 -g 1 -c 1 -n 100 \
    > $RESULT_DIR/allreduce.log 2>&1

# 2. AllGather Test  
echo "2/6 Running AllGather test..." | tee -a $RESULT_DIR/progress.log
mpirun -np 8 $MPI_OPTS /opt/nccl-tests/all_gather_perf \
    -b 1K -e 4G -f 2 -g 1 -c 1 -n 100 \
    > $RESULT_DIR/allgather.log 2>&1

# 3. Broadcast Test
echo "3/6 Running Broadcast test..." | tee -a $RESULT_DIR/progress.log
mpirun -np 8 $MPI_OPTS /opt/nccl-tests/broadcast_perf \
    -b 1K -e 2G -f 2 -g 1 -c 1 -n 100 \
    > $RESULT_DIR/broadcast.log 2>&1

# 4. ReduceScatter Test
echo "4/6 Running ReduceScatter test..." | tee -a $RESULT_DIR/progress.log
mpirun -np 8 $MPI_OPTS /opt/nccl-tests/reduce_scatter_perf \
    -b 1K -e 2G -f 2 -g 1 -c 1 -n 100 \
    > $RESULT_DIR/reducescatter.log 2>&1

# 5. AllToAll Test
echo "5/6 Running AllToAll test..." | tee -a $RESULT_DIR/progress.log
mpirun -np 8 $MPI_OPTS /opt/nccl-tests/alltoall_perf \
    -b 1K -e 1G -f 2 -g 1 -c 1 -n 50 \
    > $RESULT_DIR/alltoall.log 2>&1

# 6. SendRecv Test (P2P)
echo "6/6 Running SendRecv test..." | tee -a $RESULT_DIR/progress.log
mpirun -np 2 $MPI_OPTS /opt/nccl-tests/sendrecv_perf \
    -b 1K -e 2G -f 2 -g 1 -c 1 -n 50 \
    > $RESULT_DIR/sendrecv.log 2>&1

# Generate performance report
echo "Generating performance report..."
REPORT_FILE="$RESULT_DIR/performance-report.txt"

cat > $REPORT_FILE << EOF
=== NCCL Performance Report for p5en.48xlarge ===
Generated: $(date)
Node: $(hostname)
GPUs: 8x H200 (141GB HBM3e each)
NVLink: 4th Gen, 900 GB/s per direction
Instance: p5en.48xlarge

=== Test Results Summary ===
EOF

# Extract key metrics from each test
echo "" >> $REPORT_FILE
echo "AllReduce Performance:" >> $REPORT_FILE
grep -E "(1048576|8388608|134217728|1073741824)" $RESULT_DIR/allreduce.log | \
    awk '{printf "  %8s: %8.2f GB/s\n", $1, $6}' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "AllGather Performance:" >> $REPORT_FILE
grep -E "(1048576|8388608|134217728|1073741824)" $RESULT_DIR/allgather.log | \
    awk '{printf "  %8s: %8.2f GB/s\n", $1, $6}' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "Broadcast Performance:" >> $REPORT_FILE
grep -E "(1048576|8388608|134217728|1073741824)" $RESULT_DIR/broadcast.log | \
    awk '{printf "  %8s: %8.2f GB/s\n", $1, $6}' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "ReduceScatter Performance:" >> $REPORT_FILE
grep -E "(1048576|8388608|134217728|1073741824)" $RESULT_DIR/reducescatter.log | \
    awk '{printf "  %8s: %8.2f GB/s\n", $1, $6}' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "AllToAll Performance:" >> $REPORT_FILE
grep -E "(1048576|8388608|134217728)" $RESULT_DIR/alltoall.log | \
    awk '{printf "  %8s: %8.2f GB/s\n", $1, $6}' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "SendRecv (P2P) Performance:" >> $REPORT_FILE
grep -E "(1048576|8388608|134217728|1073741824)" $RESULT_DIR/sendrecv.log | \
    awk '{printf "  %8s: %8.2f GB/s\n", $1, $6}' >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "=== Expected Performance Baselines ===" >> $REPORT_FILE
echo "Single Node (8x H200):" >> $REPORT_FILE
echo "  - Peak aggregate bandwidth: ~1.8 TB/s" >> $REPORT_FILE
echo "  - NVLink bandwidth per GPU: ~900 GB/s" >> $REPORT_FILE
echo "  - Memory bandwidth per GPU: ~4.8 TB/s" >> $REPORT_FILE
echo "  - Latency (small messages): <10μs" >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "=== Files Generated ===" >> $REPORT_FILE
echo "  - system-info.log: System and GPU information" >> $REPORT_FILE
echo "  - allreduce.log: AllReduce detailed results" >> $REPORT_FILE
echo "  - allgather.log: AllGather detailed results" >> $REPORT_FILE
echo "  - broadcast.log: Broadcast detailed results" >> $REPORT_FILE
echo "  - reducescatter.log: ReduceScatter detailed results" >> $REPORT_FILE
echo "  - alltoall.log: AllToAll detailed results" >> $REPORT_FILE
echo "  - sendrecv.log: SendRecv (P2P) detailed results" >> $REPORT_FILE
echo "  - performance-report.txt: This summary report" >> $REPORT_FILE

echo "NCCL Benchmark Suite completed successfully!"
echo "Results saved to: $RESULT_DIR"
echo "Performance report: $REPORT_FILE"
echo ""
echo "Quick summary:"
cat $REPORT_FILE