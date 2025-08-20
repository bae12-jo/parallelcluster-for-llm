# NCCL Tests for p5en.48xlarge

This directory contains NCCL test scripts optimized for p5en.48xlarge instances with H200 GPUs.

## Prerequisites

- AWS ParallelCluster with p5en.48xlarge compute nodes
- NCCL 2.27.6+ installed
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

- **Single Node (8x H200)**: ~1.2-1.4 TB/s aggregate bandwidth (70-80% of theoretical)
- **Multi-Node**: Linear scaling with 3.2Tbps networking
- **Latency**: <10μs for small messages within node
- **NVLink**: ~900 GB/s per GPU pair

## Performance Optimization Cheatsheet for p5en.48xlarge

### Essential Environment Variables

#### Core NCCL Settings
```bash
# Enable NVLink Sharp for H200 GPUs
export NCCL_NVLS_ENABLE=1

# EFA-optimized protocol (critical for p5en)
export NCCL_PROTO=Simple
export NCCL_ALGO=Ring,Tree

# GPU Direct optimization (important for p5en)
export NCCL_NET_GDR_LEVEL=PIX

# Disable conflicting transports
export NCCL_IB_DISABLE=1
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0

# Network interface configuration
export NCCL_SOCKET_IFNAME=^docker0,lo
export NCCL_CROSS_NIC=0
```

#### AWS OFI NCCL Plugin (EFA Optimization)
```bash
# Enable EFA provider for 3.2Tbps bandwidth
export FI_PROVIDER=efa

# Critical for p5en performance
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1

# Optimize for large message sizes (LLM training)
export FI_EFA_ENABLE_SHM_TRANSFER=1
export FI_EFA_USE_HUGE_PAGE=1

# Multi-rail configuration for maximum bandwidth
export FI_EFA_NUM_MR_CACHE_ENTRIES=65536
export FI_EFA_MR_CACHE_ENABLE=1
```

#### GPU and Memory Optimization
```bash
# Use all 8x H200 GPUs
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7

# Memory optimization for 141GB HBM3e per GPU
export NCCL_BUFFSIZE=8388608
export NCCL_NTHREADS=512

# H200-specific optimizations
export CUDA_DEVICE_MAX_CONNECTIONS=32
export NCCL_MAX_NCHANNELS=32
```

### Workload-Specific Tuning

#### Large Language Model Training (500B+ parameters)
```bash
# Optimize for large AllReduce operations
export NCCL_MIN_NCHANNELS=32
export NCCL_MAX_NCHANNELS=32
export NCCL_TREE_THRESHOLD=0

# Pipeline parallelism optimization
export NCCL_LL_THRESHOLD=16384
export NCCL_LL128_THRESHOLD=131072
```

#### Multi-Node Training (2+ nodes)
```bash
# Network topology awareness
export NCCL_TOPO_DUMP_FILE=/tmp/nccl_topo.txt
export NCCL_GRAPH_DUMP_FILE=/tmp/nccl_graph.txt

# Inter-node communication optimization
export NCCL_CROSS_NIC=0
export NCCL_NET_SHARED_BUFFERS=0

# Timeout settings for large clusters
export NCCL_TIMEOUT=1800
export NCCL_BLOCKING_WAIT=1
```

### Debugging and Monitoring

#### Performance Analysis
```bash
# Enable detailed logging
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,GRAPH,ENV,NET

# Performance profiling
export NCCL_LAUNCH_MODE=PARALLEL
export NCCL_CUMEM_ENABLE=0
```

#### Network Diagnostics
```bash
# EFA diagnostics
export FI_LOG_LEVEL=info
export FI_EFA_ENABLE_SHM_TRANSFER=1

# Bandwidth testing
export NCCL_CHECK_DISABLE=0
export NCCL_DEBUG_NOCHECK=0
```

### Version Compatibility

#### Recommended Versions
- **NCCL**: v2.27.6-1 (stable, tested)
- **AWS OFI NCCL**: v1.16.2-aws (latest stable)
- **Libfabric**: v1.22.0amzn4.0 or later (required for AWS OFI NCCL)
- **CUDA**: 12.0+ for H200 support
- **EFA Driver**: Latest from AWS

#### Installation Commands
```bash
# Install stable NCCL version
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libnccl2_2.27.6-1+cuda12.0_amd64.deb
dpkg -i libnccl2_2.27.6-1+cuda12.0_amd64.deb

# Install AWS OFI NCCL plugin (requires Libfabric v1.22.0amzn4.0+)
git clone https://github.com/aws/aws-ofi-nccl.git -b v1.16.2-aws
cd aws-ofi-nccl && ./autogen.sh && ./configure && make && make install

# Verify Libfabric version
fi_info --version  # Should show v1.22.0amzn4.0 or later
```

### Performance Expectations

#### Single Node (8x H200)
- **AllReduce (1GB)**: ~1.2-1.4 TB/s aggregate (70-80% of theoretical)
- **AllGather (1GB)**: ~1.0-1.2 TB/s aggregate (70-80% of theoretical)  
- **P2P NVLink**: ~900 GB/s per direction (hardware limit)
- **Memory Copy**: ~4.8 TB/s per GPU (HBM3e bandwidth)

> **Note**: Real-world NCCL performance typically achieves 70-80% of theoretical maximum due to protocol overhead, synchronization, and network stack latency.

#### Multi-Node (2+ nodes)
- **Inter-node bandwidth**: 3.2 Tbps per node
- **Scaling efficiency**: >95% for models >100B parameters
- **Latency overhead**: <5μs additional per hop

### Quick Performance Test
```bash
# Single node bandwidth test
mpirun -np 8 /opt/nccl-tests/all_reduce_perf -b 1G -e 8G -f 2 -g 1

# Multi-node scaling test  
srun --nodes=2 --ntasks-per-node=8 /opt/nccl-tests/all_reduce_perf -b 1G -e 4G -f 2 -g 1

# P2P bandwidth verification
nvidia-smi topo -m  # Check NVLink topology
```

## Output

Test results are saved to `/fsx/nccl-results/` with timestamps.
