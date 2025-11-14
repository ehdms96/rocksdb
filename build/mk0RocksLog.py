import sys
import re

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <rocks.log> <out.csv>")
    sys.exit(1)

log_file = sys.argv[1]
out_file = sys.argv[2]

# 시간 + thread_id + ops_and 뒤의 두 숫자 캡처
pattern = re.compile(
    r"(\d{4}/\d{2}/\d{2})-(\d{2}):(\d{2}):(\d{2})\.(\d{6})\s+thread_(\d+):.*?ops_and\s+([\d\.]+),([\d\.]+)"
)

with open(log_file) as fin, open(out_file, "w") as fout:
    fout.write("time,ops_interval,ops_total\n")
    for line in fin:
        m = pattern.search(line)
        if not m:
            continue

        _, hh, mm, ss, usec, tid, ops_interval, ops_total = m.groups()

        # thread_0만 사용
        if tid != "0":
            continue

        # HH:MM:SS.ffffff → float seconds
        sec = int(hh) * 3600 + int(mm) * 60 + int(ss) + int(usec) / 1e6

        fout.write(f"{sec:.6f},{ops_interval},{ops_total}\n")

