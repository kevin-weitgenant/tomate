#include "backend.h"

#include "db.h"

#include <QDate>
#include <QDateTime>

static qint64 dayStart(const QDate &d) { return d.startOfDay().toSecsSinceEpoch(); }

static qint64 weekStart() {
    const QDate today = QDate::currentDate();
    return dayStart(today.addDays(1 - today.dayOfWeek()));
}

Backend::Backend(Db &db, Engine &engine, QObject *parent) : QObject(parent), m_db(db), m_engine(engine) {
    reloadData();
    refresh();
    // Twice a second is enough for a seconds display; the ring animates in
    // between. The tick also notices changes made by the CLI or the bar.
    m_timer.setInterval(500);
    connect(&m_timer, &QTimer::timeout, this, &Backend::refresh);
    m_timer.start();
}

int Backend::remainingSec() const {
    // Overtime: the block reached 00:00 and keeps counting, so show the
    // elapsed time climbing past the planned length.
    if (m_state.over)
        return int((m_state.elapsedMs(m_now) + 999) / 1000);
    // Round up, so a timer shows 25:00 the moment it starts and 00:01 last.
    const qint64 ms = m_state.remainingMs(m_now);
    return ms <= 0 ? 0 : int((ms + 999) / 1000);
}

double Backend::progress() const {
    const qint64 len = qint64(m_state.lengthSec()) * 1000;
    return len ? qBound(0.0, double(m_state.elapsedMs(m_now)) / double(len), 1.0) : 0.0;
}

QVariantMap Backend::cycle() const {
    const auto &c = m_state.cycle;
    return {{"presetId", c.presetId}, {"name", c.name}, {"custom", c.custom},
            {"focusSec", c.focusSec}, {"shortSec", c.shortSec}, {"longSec", c.longSec},
            {"focusMin", c.focusSec / 60.0}, {"shortMin", c.shortSec / 60.0}, {"longMin", c.longSec / 60.0},
            {"every", c.every}, {"autoBreaks", c.autoBreaks}, {"autoFocus", c.autoFocus},
            {"breaks", c.hasBreaks()}};
}

double Backend::endsAt() const {
    if (m_state.waiting || m_state.paused() || m_state.over)
        return 0;
    return (m_now + m_state.remainingMs(m_now)) / 1000.0;
}

int Backend::runningSec() const {
    return m_state.phase == "focus" && m_state.sessionId ? int(m_state.elapsedMs(m_now) / 1000) : 0;
}

int Backend::dailyGoalMin() const { return m_db.setting("daily_goal_min", "240").toInt(); }
bool Backend::sound() const { return m_db.setting("sound", "1") == "1"; }
QString Backend::dbPath() const { return m_db.path(); }

void Backend::refresh() {
    const auto events = m_engine.tick();
    Engine::notify(events, m_db);
    m_state = m_engine.state();
    m_now = m_engine.now();

    // Today, per project, including the block that is running right now.
    QMap<int, int> perProject;
    for (const auto &r : m_db.rows("SELECT project_id, SUM(duration_sec) AS s FROM sessions "
                                   "WHERE started_at >= ? AND ended_at IS NOT NULL GROUP BY project_id",
                                   {dayStart(QDate::currentDate())})) {
        const auto row = r.toMap();
        perProject[row.value("project_id").toInt()] += row.value("s").toInt();
    }
    if (const int live = runningSec())
        perProject[m_state.projectId] += live;
    m_todaySec = 0;
    m_todayByProject.clear();
    for (auto it = perProject.begin(); it != perProject.end(); ++it) {
        m_todaySec += it.value();
        int color = 0;
        for (const auto &p : m_projects)
            if (p.toMap().value("id").toInt() == it.key())
                color = p.toMap().value("color").toInt();
        m_todayByProject << QVariantMap{{"id", it.key()}, {"sec", it.value()}, {"color", color}};
    }

    // Sessions edited elsewhere (CLI, another window) or a phase that just
    // ended: reload lists so the calendar and totals follow.
    const int count = m_db.scalar("SELECT COUNT(*) + COALESCE(SUM(duration_sec), 0) FROM sessions", {}, 0).toInt();
    if (!events.isEmpty() || count != m_lastSessionCount) {
        m_lastSessionCount = count;
        reloadData();
    }
    emit ticked();
}

void Backend::after(const QList<TimerEvent> &events) {
    Engine::notify(events, m_db);
    reloadData();
    refresh();
}

void Backend::reloadData() {
    const qint64 today = dayStart(QDate::currentDate());
    m_presets.clear();
    for (const auto &r : m_db.rows("SELECT * FROM presets ORDER BY sort, id")) {
        const auto p = r.toMap();
        m_presets << QVariantMap{
            {"id", p.value("id")}, {"name", p.value("name")},
            {"focusMin", p.value("focus_sec").toInt() / 60.0}, {"shortMin", p.value("short_sec").toInt() / 60.0},
            {"longMin", p.value("long_sec").toInt() / 60.0}, {"every", p.value("long_every")},
            {"autoBreaks", p.value("auto_breaks").toBool()}, {"autoFocus", p.value("auto_focus").toBool()},
            {"projects", m_db.scalar("SELECT COUNT(*) FROM projects WHERE preset_id = ?", {p.value("id")}, 0)}};
    }
    m_projects.clear();
    for (const auto &r : m_db.rows(
             "SELECT p.id, p.name, p.color, p.preset_id, p.archived, pr.name AS preset_name, "
             "  COALESCE(SUM(CASE WHEN s.started_at >= ? THEN s.duration_sec END), 0) AS today_sec, "
             "  COALESCE(SUM(CASE WHEN s.started_at >= ? THEN s.duration_sec END), 0) AS week_sec, "
             "  COALESCE(SUM(s.duration_sec), 0) AS total_sec, COUNT(s.id) AS session_count "
             "FROM projects p LEFT JOIN presets pr ON pr.id = p.preset_id "
             "LEFT JOIN sessions s ON s.project_id = p.id AND s.ended_at IS NOT NULL "
             "GROUP BY p.id ORDER BY p.archived, p.id",
             {today, weekStart()})) {
        const auto p = r.toMap();
        m_projects << QVariantMap{
            {"id", p.value("id")}, {"name", p.value("name")}, {"color", p.value("color")},
            {"presetId", p.value("preset_id").toInt()}, {"presetName", p.value("preset_name").toString()},
            {"archived", p.value("archived").toBool()}, {"todaySec", p.value("today_sec")},
            {"weekSec", p.value("week_sec")}, {"totalSec", p.value("total_sec")},
            {"sessions", p.value("session_count")}};
    }
    ++m_revision;
    emit dataChanged();
}

// Timer ------------------------------------------------------------------

void Backend::toggle() { after(m_engine.toggle()); }
void Backend::skip() { after(m_engine.skip()); }
void Backend::stop(bool discard) { after(m_engine.stop(discard)); }
void Backend::setProject(int id) { after(m_engine.setProject(id)); }
void Backend::setNote(const QString &note) { after(m_engine.setNote(note)); }
void Backend::usePreset(int id) { after(m_engine.usePreset(id)); }

void Backend::setCustomCycle(int focusMin, int breakMin, int rounds) {
    after(m_engine.setCustomCycle(focusMin * 60, breakMin * 60, rounds));
}

int Backend::saveCycleAsPreset(const QString &name) {
    const auto c = m_state.cycle;
    const int id = createPreset({{"name", name.trimmed().isEmpty() ? tr("My preset") : name},
                                 {"focusMin", c.focusSec / 60.0}, {"shortMin", c.shortSec / 60.0},
                                 {"longMin", c.longSec / 60.0}, {"every", c.every},
                                 {"autoBreaks", c.autoBreaks}, {"autoFocus", c.autoFocus}});
    usePreset(id);
    return id;
}

// Projects ---------------------------------------------------------------

int Backend::createProject(const QString &name, int color, int presetId) {
    auto q = m_db.exec("INSERT INTO projects(name, color, preset_id, created_at) VALUES(?, ?, ?, ?)",
                       {name.trimmed(), color, presetId > 0 ? QVariant(presetId) : QVariant(),
                        QDateTime::currentSecsSinceEpoch()});
    const int id = q.lastInsertId().toInt();
    reloadData();
    return id;
}

void Backend::updateProject(int id, const QString &name, int color, int presetId) {
    m_db.exec("UPDATE projects SET name = ?, color = ?, preset_id = ? WHERE id = ?",
              {name.trimmed(), color, presetId > 0 ? QVariant(presetId) : QVariant(), id});
    // A new default preset shows on the timer straight away when it is idle.
    if (id == m_state.projectId && m_state.idle() && !m_state.cycle.custom)
        m_engine.setProject(id);
    after({});
}

void Backend::setArchived(int id, bool archived) {
    m_db.exec("UPDATE projects SET archived = ? WHERE id = ?", {archived ? 1 : 0, id});
    after({});
}

void Backend::deleteProject(int id) {
    if (id == m_state.projectId && m_state.sessionId)
        m_engine.stop();
    m_db.exec("DELETE FROM sessions WHERE project_id = ?", {id});
    m_db.exec("DELETE FROM projects WHERE id = ?", {id});
    after({});
}

// Presets ----------------------------------------------------------------

static QVariantList presetArgs(const QVariantMap &p) {
    // Focus is at least a second; a break of 0 means no break.
    auto sec = [&](const char *k, double fallback, int least) {
        return qMax(least, int(p.value(k, fallback).toDouble() * 60));
    };
    return {p.value("name").toString().trimmed(), sec("focusMin", 25, 1), sec("shortMin", 5, 0), sec("longMin", 15, 0),
            qBound(1, p.value("every", 4).toInt(), 99), p.value("autoBreaks", true).toBool() ? 1 : 0,
            p.value("autoFocus", false).toBool() ? 1 : 0};
}

int Backend::createPreset(const QVariantMap &p) {
    auto args = presetArgs(p);
    args << m_db.scalar("SELECT COALESCE(MAX(sort), 0) + 1 FROM presets", {}, 0);
    auto q = m_db.exec("INSERT INTO presets(name, focus_sec, short_sec, long_sec, long_every, auto_breaks, auto_focus, sort) "
                       "VALUES(?, ?, ?, ?, ?, ?, ?, ?)", args);
    const int id = q.lastInsertId().toInt();
    reloadData();
    return id;
}

void Backend::updatePreset(int id, const QVariantMap &p) {
    auto args = presetArgs(p);
    args << id;
    m_db.exec("UPDATE presets SET name = ?, focus_sec = ?, short_sec = ?, long_sec = ?, long_every = ?, "
              "auto_breaks = ?, auto_focus = ? WHERE id = ?", args);
    // Editing the preset in use changes the running cycle too, unless the
    // cycle has its own custom times.
    if (m_state.cycle.presetId == id && !m_state.cycle.custom)
        m_engine.usePreset(id);
    after({});
}

bool Backend::deletePreset(int id) {
    if (m_db.scalar("SELECT COUNT(*) FROM presets", {}, 0).toInt() <= 1)
        return false;
    m_db.exec("DELETE FROM presets WHERE id = ?", {id});
    if (m_state.cycle.presetId == id && !m_state.cycle.custom)
        m_engine.usePreset(0);
    after({});
    return true;
}

// Sessions ---------------------------------------------------------------

QVariantList Backend::sessions(double fromSec, double toSec) const {
    QVariantList out;
    const qint64 now = m_now / 1000;
    for (const auto &r : m_db.rows(
             "SELECT s.*, p.name AS project_name, p.color AS color FROM sessions s "
             "JOIN projects p ON p.id = s.project_id "
             "WHERE s.started_at < ? AND COALESCE(s.ended_at, ?) > ? ORDER BY s.started_at",
             {qint64(toSec), now, qint64(fromSec)})) {
        auto s = r.toMap();
        const bool live = s.value("ended_at").isNull();
        // An open row that isn't the timer's own session was left by a crash
        // before this version could close it; show it as stopped.
        if (live && s.value("id").toInt() != m_state.sessionId)
            continue;
        out << QVariantMap{
            {"id", s.value("id")}, {"projectId", s.value("project_id")}, {"project", s.value("project_name")},
            {"color", s.value("color")}, {"start", s.value("started_at").toDouble()},
            {"end", live ? double(now) : s.value("ended_at").toDouble()},
            {"durationSec", live ? runningSec() : s.value("duration_sec").toInt()},
            {"completed", s.value("completed").toBool()}, {"kind", s.value("kind")},
            {"note", s.value("note")}, {"running", live}};
    }
    return out;
}

QVariantList Backend::dayTotals(double fromSec, int days) const {
    QVariantList out;
    QDate day = QDateTime::fromSecsSinceEpoch(qint64(fromSec)).date();
    for (int i = 0; i < days; ++i, day = day.addDays(1)) {
        const qint64 a = dayStart(day), b = dayStart(day.addDays(1));
        int sec = m_db.scalar("SELECT COALESCE(SUM(duration_sec), 0) FROM sessions "
                              "WHERE started_at >= ? AND started_at < ? AND ended_at IS NOT NULL", {a, b}, 0).toInt();
        if (m_state.sessionId && m_state.phaseStart / 1000 >= a && m_state.phaseStart / 1000 < b)
            sec += runningSec();
        out << sec;
    }
    return out;
}

int Backend::addSession(int projectId, double startSec, double endSec, const QString &note) {
    if (endSec <= startSec)
        return 0;
    auto q = m_db.exec("INSERT INTO sessions(project_id, started_at, ended_at, duration_sec, planned_sec, kind, completed, note) "
                       "VALUES(?, ?, ?, ?, ?, 'manual', 1, ?)",
                       {projectId, qint64(startSec), qint64(endSec), int(endSec - startSec), int(endSec - startSec),
                        note.trimmed()});
    const int id = q.lastInsertId().toInt();
    after({});
    return id;
}

void Backend::updateSession(int id, int projectId, double startSec, double endSec, const QString &note) {
    if (id == m_state.sessionId) {
        // The running block keeps its clock; only what it belongs to can change.
        if (projectId != m_state.projectId)
            m_engine.setProject(projectId);
        m_engine.setNote(note);
    } else if (endSec > startSec) {
        m_db.exec("UPDATE sessions SET project_id = ?, started_at = ?, ended_at = ?, duration_sec = ?, note = ? WHERE id = ?",
                  {projectId, qint64(startSec), qint64(endSec), int(endSec - startSec), note.trimmed(), id});
    }
    after({});
}

void Backend::deleteSession(int id) {
    if (id == m_state.sessionId)
        m_engine.stop();
    m_db.exec("DELETE FROM sessions WHERE id = ?", {id});
    after({});
}

// Settings ---------------------------------------------------------------

void Backend::setDailyGoalMin(int minutes) {
    m_db.setSetting("daily_goal_min", QString::number(qBound(0, minutes, 24 * 60)));
    after({});
}

void Backend::setSound(bool on) {
    m_db.setSetting("sound", on ? "1" : "0");
    after({});
}
