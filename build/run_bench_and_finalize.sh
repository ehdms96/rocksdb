#!/usr/bin/env bash
# run_bench_and_finalize.sh
# 1) iostat 모니터 시작
# 2) RocksDB db_bench 실행
# 3) 종료 시 BENCH_DONE:<로그경로> 알림 (virtio-serial 우선, 실패 시 TCP 대체)
# 4) 모니터 SIGINT 종료
# 5) 후처리 파이썬 실행

set -Eeuo pipefail

# ===== 사용자 설정(환경변수로 덮어쓰기 가능) =====
TAG="${TAG:-exp1}"                                # 실험 태그 (PID/파일명 구분용)
LOG_DIR="${LOG_DIR:-/mnt/tmpfs}"                  # 로그 디렉토리
LOG_SUFFIX="${LOG_SUFFIX:-multi_r4G_128th_C}"   # Rocks 로그 접미사
VIRTIO_PORT="${VIRTIO_PORT:-/dev/virtio-ports/org.femu.log}"
TCP_HOST="${TCP_HOST:-10.0.2.2}"                  # SLIRP 네트워크에서 호스트
TCP_PORT="${TCP_PORT:-5555}"

# 모니터/후처리 스크립트 경로
MONITOR_SCRIPT="${MONITOR_SCRIPT:-/root/monitor_io.sh}"              # 질문에서 위치: /
POST_ROCKS_PY="${POST_ROCKS_PY:-mk0xthead_Rocks.py}"            # 현재 디렉토리 기준(원문 그대로)
POST_IOSTAT_PY="${POST_IOSTAT_PY:-/root/interval_iostat_mklog.py}"   # 절대경로(원문 그대로)

# db_bench 커맨드를 배열로! (root면 sudo 생략)
if [[ $EUID -eq 0 ]]; then
  DB_BENCH_CMD=(/home/femu/rocksdb/db_bench)
else
  DB_BENCH_CMD=(sudo /home/femu/rocksdb/db_bench)
fi
DB_ARGS_DEFAULT=(
  --db=/mnt/f2fs/dbbench
  --benchmarks=YCSBLOAD,YCSBB,stats
  --use_direct_io_for_flush_and_compaction
  --compression_type=none
  --num_record=21760000
  --num_op=650000 #A : 350000 / B : 550000 / C : 650000
  --threads=128
  --max_background_jobs=8
  --write_buffer_size=134217728
  --target_file_size_base=134217728
  --stats_interval_seconds=1
)
DB_ARGS=("${DB_ARGS_DEFAULT[@]}" "$@")   # 전달 인자로 덮어쓰기 허용

# ===== 경로/파일명 구성 =====
ts="$(date +'%Y%m%d_%H%M%S')"
ROCKS_LOG="${LOG_DIR}/${ts}_rocks_${LOG_SUFFIX}.log"
IOSTAT_LOG="${LOG_DIR}/${ts}_iostat_${LOG_SUFFIX}.log"
DEVSTAT_LOG="${ts}_devstat_${LOG_SUFFIX}.log"
PIDFILE="/run/monitor_io.${TAG}.pid"
OUT_ROCKS_CSV="${LOG_DIR}/${ts}_summary_rocks_${LOG_SUFFIX}.csv"
OUT_IOSTAT_CSV="${LOG_DIR}/${ts}_summary_iostat_${LOG_SUFFIX}.csv"

mkdir -p "$LOG_DIR"
# /run 은 보통 이미 존재. PIDFILE 쓸 권한 문제 있으면 sudo tee 사용.

# ===== 알림/정리 함수 =====
notify_done() {
  local msg="BENCH_DONE:${DEVSTAT_LOG}"
  local tries=10
  local ok=1

  for ((i=1; i<=tries; i++)); do
    # 1) virtio-serial (있으면 전송 시도)
    if [[ -e "${VIRTIO_PORT}" ]]; then
      printf '%s\n' "$msg" | sudo tee "${VIRTIO_PORT}" >/dev/null 2>&1 && ok=0
    fi
    # 2) TCP도 병행 전송(호스트에서 nc -lk 5555)
    if command -v nc >/dev/null 2>&1; then
      printf '%s\n' "$msg" | nc -w 1 "${TCP_HOST}" "${TCP_PORT}" >/dev/null 2>&1 && ok=0
    fi

    (( ok == 0 )) && break
    sleep 0.5
  done

  if (( ok != 0 )); then
    echo "[warn] notify_done 실패: virtio/TCP 모두 응답 불확실" >&2
  else
    echo "[info] notify_done OK"
  fi
  return $ok
}

stop_monitor() {
  if [[ -s "$PIDFILE" ]]; then
    local pid
    pid="$(cat "$PIDFILE")"
    if kill -0 "$pid" 2>/dev/null; then
      kill -INT "$pid" 2>/dev/null || sudo kill -INT "$pid" 2>/dev/null || true
      sleep 2
      kill -0 "$pid" 2>/dev/null && (kill -TERM "$pid" 2>/dev/null || sudo kill -TERM "$pid" 2>/dev/null || true)
      sleep 1
      kill -0 "$pid" 2>/dev/null && (kill -KILL "$pid" 2>/dev/null || sudo kill -KILL "$pid" 2>/dev/null || true)
    fi
  fi
}

cleanup() {
  trap - EXIT INT TERM   # 재진입 방지
  # 벤치 성공/실패/중단과 관계없이 항상 실행
  notify_done || true
  stop_monitor || true

  # ===== 후처리 =====
  # rocks 로그 요약
  if [[ -s "$ROCKS_LOG" ]]; then
    echo "[post] Rocks summary -> $OUT_ROCKS_CSV"
    python3 "$POST_ROCKS_PY" "$ROCKS_LOG" "$OUT_ROCKS_CSV" 128.0 || echo "[warn] $POST_ROCKS_PY 실패"
  else
    echo "[warn] Rocks 로그가 비어있음: $ROCKS_LOG"
  fi
  # iostat 요약
  if [[ -s "$IOSTAT_LOG" ]]; then
    echo "[post] iostat summary -> $OUT_IOSTAT_CSV"
    python3 "$POST_IOSTAT_PY" "$IOSTAT_LOG" "$OUT_IOSTAT_CSV" || echo "[warn] $POST_IOSTAT_PY 실패"
  else
    echo "[warn] iostat 로그가 비어있음: $IOSTAT_LOG"
  fi

  # ----- 백업 복사 -----
  dest="/backup/log/iostat_rocksdb"
  mkdir -p "$dest" || true

  # 매칭되는 파일만 선별 (rocks/iostat 로그 + 요약 csv)
  # nullglob: 매칭 없으면 빈 목록
  shopt -s nullglob
  files=(
    "$LOG_DIR/${ts}_"*.log
    "$LOG_DIR/${ts}_"*.csv
  )
  shopt -u nullglob

  if ((${#files[@]})); then
    # reflink 지원 FS면 순간복사, 그 외엔 일반 복사
    cp --reflink=auto --sparse=always -t "$dest" "${files[@]}" || echo "[warn] backup copy failed"
    echo "[post] copying ${#files[@]} files to $dest"
  else
    echo "[post] no files to backup from $LOG_DIR"
  fi
}
trap cleanup EXIT INT TERM

# ===== 1) iostat 모니터 시작 (PID 저장) =====
if [[ ! -x "$MONITOR_SCRIPT" ]]; then
  echo "[error] MONITOR_SCRIPT 실행 불가: $MONITOR_SCRIPT" >&2
  exit 1
fi

# 백그라운드 실행 + PID 기록 (권한 문제 대비해 sudo tee)
# monitor_io.sh 내부는 stdout으로 내보내고, 여기서 리다이렉션으로 파일에 저장
"$MONITOR_SCRIPT" &> "$IOSTAT_LOG" &
echo $! | sudo tee "$PIDFILE" >/dev/null
echo "[info] monitor start: pid=$(cat "$PIDFILE"), log=$IOSTAT_LOG"

# ===== 2) RocksDB 벤치 실행 =====
echo "[info] db_bench 시작 → ${ROCKS_LOG}"
"${DB_BENCH_CMD[@]}" "${DB_ARGS[@]}" &> "${ROCKS_LOG}"
ec=$?
echo "[info] db_bench 종료 코드: $ec"

# 이후 처리는 trap(cleanup)에서 자동 수행

