#!/bin/bash

echo "========== RocksDB with FS  =========="
echo ""

if [ -z "$1" ]
then
        echo "$0 FS path (ex: /mnt/f2fs, /mnt/multi)"
        exit 1
fi

if [ ! $2 ]
then
        echo "$2 background thread num (1/ 2/ 4/ 8/ 12/ 16)"
        exit 1
fi

if [ ! $3 ]
then
	echo "$3 input num (ex: LOAD 21760000 / A 350000 / B 550000 / C 650000)"
        exit 1
fi

if [ ! $4 ]
then
	echo "$4 workload (ex: YCSBLOAD,YCSBA / YCSBLOAD,YCSBB / YCSBLOAD,YCSBC / YCSBLOAD,YCSBD)"
	echo "$4 workload (ex: fillrandom,overwrite)"
	exit 1
fi


echo ""
echo "Init filesystem (Zenfs)"
rm -r $1/zns_zenfs_aux01/
blkzone reset /dev/nvme1n1

max_bk_jobs=$2
num=$3

num_record=$3
num_op=$(expr $num_record)

echo "ycsb IO thread is 128 / BK jobs : $max_bk_jobs / num record : $3 / num_op : $num_op"

plugin/zenfs/util/zenfs mkfs --zbd=/nvme1n1 --aux_path=$1/zns_zenfs_aux01/ --enable_gc=true --force

echo "Complete!"


sleep 1


if [[ $4 == YCSB* ]]
then 
	echo "macro benchmark"
	./db_bench --fs_uri=zenfs://dev:nvme1n1 --benchmarks=$4,stats --use_direct_io_for_flush_and_compaction --compression_type=none --num_record=21760000 --num_op=$num_op --threads=128 --max_background_jobs=$max_bk_jobs --write_buffer_size=134217728 --target_file_size_base=134217728 --stats_interval_seconds=1
else
	echo "micro benchmark"
        ./db_bench --fs_uri=zenfs://dev:nvme1n1  --benchmarks=$4,stats --use_direct_io_for_flush_and_compaction --compression_type=none --num=$num_record --max_background_jobs=$max_bk_jobs --stats_interval_seconds=1 #
fi
