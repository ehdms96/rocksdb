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
	echo "$3 input num (ex: 4000000 / 5000000 / 6000000)"
        exit 1
fi

if [ ! $4 ]
then
	echo "$4 workload (ex: YCSBLOAD,YCSBA / YCSBLOAD,YCSBB / YCSBLOAD,YCSBC / YCSBLOAD,YCSBD)"
	echo "$4 workload (ex: fillrandom, overwrite)"
	exit 1
fi


echo ""
echo "Init filesystem"
rm -r $1/dbbench

max_bk_jobs=$2
num=$3

num_record=$3
num_op=$(expr $num_record)

echo "ycsb IO thread is 64 / BK jobs : $max_bk_jobs / num record : $3 / num_op : $num_op"

echo "Complete!"


sleep 1


if [[ $4 == YCSB* ]]
then 
	echo "macro benchmark"
	./db_bench --db=$1/dbbench --benchmarks=$4,stats --use_direct_io_for_flush_and_compaction --compression_type=none --num_record=$num_record --num_op=$num_op --max_background_jobs=$max_bk_jobs --stats_interval_seconds=1 --use_existing_db=true #--disable_wal --use_existing_db=true --num_op=$num_op
else
	echo "micro benchmark"
        ./db_bench --db=$1/dbbench --benchmarks=$4,stats --use_direct_io_for_flush_and_compaction --compression_type=none --num=$num_record --max_background_jobs=$max_bk_jobs --stats_interval_seconds=1 #
fi
