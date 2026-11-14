#!/usr/bin/env python3
"""Fills a fresh Tomate database with made-up projects and sessions for
screenshots. Usage: TOMATE_DB=/tmp/demo.db tomate status; tools/demo_data.py /tmp/demo.db"""
import datetime as dt
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
db.execute("UPDATE projects SET name = 'Client portal' WHERE id = 1")
db.execute("INSERT INTO projects(name, color, preset_id, created_at) VALUES"
           "('Side project', 1, 2, 0), ('Study', 2, 1, 0), ('Admin', 3, 3, 0)")
today = dt.date.today()
monday = today - dt.timedelta(days=today.weekday())
# (hour, minute, minutes, project, note) per weekday of the current week.
week = {
    0: [(9, 0, 50, 1, ""), (10, 0, 100, 1, "API review"), (14, 0, 25, 4, "Email"), (15, 0, 100, 2, "")],
    1: [(8, 30, 100, 3, "Rust book ch. 8"), (10, 30, 100, 1, "Sprint review prep"), (16, 0, 50, 1, "")],
    2: [(9, 0, 150, 1, "Login flow"), (13, 30, 100, 2, "Sync worker")],
    3: [(10, 0, 25, 4, ""), (10, 30, 100, 1, "Bug triage"), (14, 0, 100, 1, "")],
    4: [(9, 0, 50, 3, ""), (11, 0, 100, 2, "Release notes")],
    5: [(9, 0, 50, 2, "")],
}
for day_index, blocks in week.items():
    day = monday + dt.timedelta(days=day_index)
    if day > today:
        continue
    for hour, minute, minutes, project, note in blocks:
        start = int(dt.datetime(day.year, day.month, day.day, hour, minute).timestamp())
        if start + minutes * 60 > dt.datetime.now().timestamp():
            continue
        db.execute("INSERT INTO sessions(project_id, started_at, ended_at, duration_sec, planned_sec, kind, completed, note)"
                   " VALUES(?, ?, ?, ?, ?, 'focus', 1, ?)", (project, start, start + minutes * 60, minutes * 60, minutes * 60, note))
# Earlier weekdays, for the month heatmap.
for back in range(1, 40):
    day = monday - dt.timedelta(days=back)
    if day.weekday() > 4:
        continue
    start = int(dt.datetime(day.year, day.month, day.day, 9, 0).timestamp())
    minutes = [60, 120, 180, 240, 90][back % 5]
    db.execute("INSERT INTO sessions(project_id, started_at, ended_at, duration_sec, planned_sec, completed)"
               " VALUES(?, ?, ?, ?, ?, 1)", (1 + back % 3, start, start + minutes * 60, minutes * 60, minutes * 60))
db.commit()
