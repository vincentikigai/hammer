#!/usr/bin/env python3
import os
import re
import sys
from datetime import datetime

def format_hms(seconds):
    if seconds < 0:
        seconds = 0
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    return f"{h:02d}:{m:02d}:{s:02d}"

def parse_time_sec(time_str):
    parts = time_str.strip().split(":")
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    return 0

def clean_report_file(file_path, min_duration=0):
    if not os.path.exists(file_path):
        print(f"- {os.path.basename(file_path)} : File not found (skipping)")
        return

    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    if not lines:
        print(f"- {os.path.basename(file_path)} : Empty file (skipping)")
        return

    # Extract date from filename report_YYYY-MM-DD.md
    base = os.path.basename(file_path)
    date_match = re.search(r"report_(\d{4}-\d{2}-\d{2})\.md", base)
    date_str = date_match.group(1) if date_match else "Report"

    # Regex for table session rows: | HH:MM:SS | HH:MM:SS | **HH:MM:SS** |
    row_re = re.compile(r"\|\s*(\d{2}:\d{2}:\d{2})\s*\|\s*(\d{2}:\d{2}:\d{2})\s*\|\s*\*?\*?(\d{2}:\d{2}:\d{2})\*?\*?\s*\|")

    raw_sessions = []
    for line in lines:
        match = row_re.search(line)
        if match:
            start_str, end_str, _ = match.groups()
            start_sec = parse_time_sec(start_str)
            end_sec = parse_time_sec(end_str)
            duration_sec = end_sec - start_sec

            if duration_sec >= min_duration:
                raw_sessions.append({
                    "start": start_str,
                    "end": end_str,
                    "start_sec": start_sec,
                    "end_sec": end_sec,
                    "duration_sec": duration_sec
                })

    if not raw_sessions:
        print(f"- {os.path.basename(file_path)} : No session rows found.")
        return

    # Group by start_sec and pick max end_sec
    grouped = {}
    for sess in raw_sessions:
        s_sec = sess["start_sec"]
        if s_sec not in grouped or sess["end_sec"] > grouped[s_sec]["end_sec"]:
            grouped[s_sec] = sess

    # Sort chronologically by start_sec
    sorted_sessions = sorted(grouped.values(), key=lambda x: x["start_sec"])

    # Calculate total duration
    total_sec = sum(s["duration_sec"] for s in sorted_sessions)
    total_hms = format_hms(total_sec)

    # Build clean markdown
    out = []
    out.append(f"# Work Time Report - {date_str}\n")
    out.append(f"- **Total Duration**: {total_hms}\n")
    out.append(f"- **Total Sessions**: {len(sorted_sessions)}\n\n")
    out.append("## Session Details\n\n")
    out.append("| Start | End | Duration |\n")
    out.append("| :--- | :--- | :--- |\n")

    for i, s in enumerate(sorted_sessions):
        dur_hms = format_hms(s["duration_sec"])
        out.append(f"| {s['start']} | {s['end']} | **{dur_hms}** |\n")

        if i < len(sorted_sessions) - 1:
            nxt = sorted_sessions[i + 1]
            break_sec = nxt["start_sec"] - s["end_sec"]
            if break_sec > 0:
                break_hms = format_hms(break_sec)
                out.append(f"| _Break_ | _{break_hms}_ | _Interruption_ |\n")

    with open(file_path, "w", encoding="utf-8") as f:
        f.writelines(out)

    print(f"+ {os.path.basename(file_path)} : Fixed! Cleaned to {len(sorted_sessions)} session(s), Total Duration: {total_hms}")

def main():
    data_folder = os.getenv("ACTIVE_TIME_FOLDER", r"C:\Users\sim\OneDrive\WorkTime")
    if len(sys.argv) > 1:
        data_folder = sys.argv[1]

    print("==========================================")
    print(" Work Time Report Cleaner (Python)")
    print(f" Target Directory: {data_folder}")
    print("==========================================")

    dates = ["2026-08-16", "2026-08-17", "2026-08-18", "2026-08-19", "2026-08-20", "2026-08-21", "2026-08-22"]
    
    for d in dates:
        fp = os.path.join(data_folder, f"report_{d}.md")
        clean_report_file(fp)

    print("\nCleanup finished!")

if __name__ == "__main__":
    main()
