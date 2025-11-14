import sys
import re

if len(sys.argv) != 4:
    print(f"Usage: {sys.argv[0]} <rocks.log> <out.csv> <thread>")
    sys.exit(1)

log_file = sys.argv[1]
out_file = sys.argv[2]
n_thread = sys.argv[3]

# thread_0 라인 파싱: 시간 + thread_id + ops_and 뒤의 두 숫자
line_re = re.compile(
    r"(\d{4}/\d{2}/\d{2})-(\d{2}):(\d{2}):(\d{2})\.(\d{6})\s+thread_(\d+):.*?ops_and\s+([\d\.]+),([\d\.]+)"
)

# 페이즈 전환 키워드
YCSBLOAD_SUMMARY_RE = re.compile(r"\bYCSBLOAD\s*:")  # 예: "YCSBLOAD     : ..."
YCSBA_SUMMARY_RE   = re.compile(r"\bYCSBA\s*:")      # 예: "YCSBA        : ..."

# YCSBA에서 곱할 계수
YCSBA_MULTIPLIER = float(n_thread)

ycsb_a_phase = False  # YCSBLOAD 요약 라인 이후를 YCSBA 페이즈로 간주

with open(log_file) as fin, open(out_file, "w") as fout:
    # 출력 포맷 유지
    fout.write("time,ops_interval,ops_total\n")

    for line in fin:
        # 페이즈 전환 감지
        if YCSBLOAD_SUMMARY_RE.search(line):
            # 이 라인 이후부터 들어오는 thread_* 진행 로그는 YCSBA로 간주
            ycsb_a_phase = True
            continue
        if YCSBA_SUMMARY_RE.search(line):
            # YCSBA 전체 요약이 나오면 끝났다고 보고 플래그를 내려도 되고 유지해도 무방
            # 여기서는 그대로 유지(로그 후속 처리 영향 없도록)
            pass

        m = line_re.search(line)
        if not m:
            continue

        _, hh, mm, ss, usec, tid, ops_interval, ops_total = m.groups()

        # thread_0만 사용
        if int(tid) != 0:
            continue

        # HH:MM:SS.ffffff → float seconds
        sec = int(hh) * 3600 + int(mm) * 60 + int(ss) + int(usec) / 1e6

        # YCSBA 페이즈면 ×64
        if ycsb_a_phase:
            oi = float(ops_interval) * YCSBA_MULTIPLIER
            ot = float(ops_total) * YCSBA_MULTIPLIER
        else:
            oi = float(ops_interval)
            ot = float(ops_total)

        fout.write(f"{sec:.6f},{oi:.1f},{ot:.1f}\n")

