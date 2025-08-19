# NCCL Tests for p5en.48xlarge

This directory contains NCCL test scripts optimized for p5en.48xlarge instances with H200 GPUs.

## Prerequisites

- AWS ParallelCluster with p5en.48xlarge compute nodes
- NCCL 2.27.7+ installed
- AWS OFI NCCL plugin for EFA support
- CUDA 12.0+ toolkit

## Test Scripts

- `nccl-allreduce-test.sbatch` - AllReduce bandwidth and latency test
- `nccl-allgather-test.sbatch` - AllGather performance test  
- `nccl-broadcast-test.sbatch` - Broadcast performance test
- `nccl-p2p-test.sbatch` - Point-to-point bandwidth test
- `nccl-multi-node-test.sbatch` - Multi-node scaling test
- `install-nccl-tests.sh` - Installation script for NCCL tests

## Usage

### Setup (after running post-install.sh on LoginNode)

1. NCCL test scripts are automatically copied to `/fsx/nccl-tests/`
2. SSH to a compute node or submit from LoginNode:
   ```bash
   # Install NCCL tests (run once on any compute node)
   srun --nodes=1 --ntasks=1 --gpus=1 /fsx/nccl-tests/install-nccl-tests.sh
   ```

### Running Tests

1. Run individual tests from LoginNode:
   ```bash
   sbatch /fsx/nccl-tests/nccl-allreduce-test.sbatch
   sbatch /fsx/nccl-tests/nccl-allgather-test.sbatch
   sbatch /fsx/nccl-tests/nccl-broadcast-test.sbatch
   sbatch /fsx/nccl-tests/nccl-p2p-test.sbatch
   ```

2. Run comprehensive benchmark suite:
   ```bash
   sbatch /fsx/nccl-tests/nccl-benchmark-suite.sbatch
   ```

3. Run multi-node scaling test:
   ```bash
   sbatch /fsx/nccl-tests/nccl-multi-node-test.sbatch
   ```

## Expected Performance (p5en.48xlarge)

- **Single Node (8x H200)**: ~1.8 TB/s aggregate bandwidth
- **Multi-Node**: Linear scaling with 3.2Tbps networking
- **Latency**: <10μs for small messages within node
- **NVLink**: ~900 GB/s per GPU pair

## Output

Test results are saved to `/fsx/nccl-results/` with timestamps.