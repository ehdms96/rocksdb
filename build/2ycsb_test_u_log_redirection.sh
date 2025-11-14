#!/bin/bash

echo "========== RocksDB with FS  =========="
echo ""

if [ -z "$1" ]
then
        echo "$0 FS path (ex: f2fs, multi)"
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
        exit 1
fi

DATE=$(date +%Y%m%d_%H%M%S)
FILENAME=${DATE}_ycsb_$1_$2_$3_$4

CSVFILE=${FILENAME}.csv
LOGFILE=/mnt/tmpfs/${FILENAME}.log

BACKUP=/backup/log/dbbench/YCSB/

echo "$FILENAME"
echo "start hytrack background job"
./control_logging.sh start "$CSVFILE" &
echo ""

echo "ycsb test redirection"
./2ycsb_u_test.sh /mnt/$1 $2 $3 $4 > "$LOGFILE" 2>&1 && mv "$LOGFILE" "$BACKUP"
echo "** ycsb log file move to /BACKUP"
echo ""

echo "sleep 5 sec & stop hytrack"
sleep 5
./control_logging.sh stop
mv /mnt/tmpfs/${CSVFILE} $BACKUP
echo "** hytrack log file move to /BACKUP"
echo ""

echo "Success"
