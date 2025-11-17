#!/bin/bash

echo "========== RocksDB with ZNS SSD =========="
echo ""

if [ ! $1 ]
then
        echo "$0 workload_type (1: YCSBLOAD,YCSBA, 2:, 3:)"
        exit 1
fi

echo ""
echo "Init filesystem (ZenFS)"

if [ -d /mnt/tmpfs/zenfs_aux01 ]
then
 rm -r /mnt/tmpfs/zenfs_aux01
fi

start_zone=0
num_zones=512
ao_zones=7

blkzone reset /dev/nvme1n1
../plugin/zenfs/util/zenfs mkfs --zbd=nvme1n1 --aux_path=/mnt/tmpfs/zenfs_aux01 \
	--enable_gc=true --start_zone=$start_zone --num_zones=$num_zones --ao_zones=$ao_zones --force

echo "Complete!"

sleep 1

# ZenFS
output_file="/mnt/tmpfs/Z_64G_T8_WAL_CNS_$(date +%Y%m%d_%H%M%S)_I1.log"

if [ $1 -eq 1 ]; then
  echo "YCSBLOAD,YCSBA starts"
  ./db_bench --fs_uri=zenfs://dev:nvme1n1/$start_zone\/$num_zones\/$ao_zones \
           --benchmarks=YCSBLOAD,YCSBA,stats \
           --use_direct_io_for_flush_and_compaction \
	   --compression_type=none \
	   --num_record=25000000 --num_op=350000 --threads=64 \
           --max_background_jobs=8 \
	   --write_buffer_size=134217728 --target_file_size_base=134217728 \
	   --stats_interval_seconds=1 &> $output_file
fi

sudo ../plugin/zenfs/util/zenfs df --zbd=nvme1n1
