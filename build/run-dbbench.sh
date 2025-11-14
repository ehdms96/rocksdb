LOG="/mnt/tmpfs/rocks_output_$(date +%Y%m%d_%H%M%S)_$1"; \
trap 'printf "BENCH_DONE:%s\n" "$LOG" > /dev/virtio-ports/org.femu.log' EXIT; \
sudo ./db_bench --db=/mnt/f2fs/dbbench --benchmarks=YCSBLOAD,YCSBA,stats \
  --use_direct_io_for_flush_and_compaction --compression_type=none \
  --num_record=21760000 --num_op=350000 --threads=128 \
  --max_background_jobs=8 --write_buffer_size=134217728 \
  --target_file_size_base=134217728 --stats_interval_seconds=1 \
  &> "$LOG"

