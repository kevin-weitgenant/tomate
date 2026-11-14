#include "engine.h"

#include "db.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcess>
#include <QStandardPaths>

// A focus block that would start more than this long ago (because nothing
// was running to start it on time) waits for you instead of inventing work.
static constexpr qint64 LateMs = 60 * 1000;
// Stopping within the first minute doesn't leave a block on the calendar.
static constexpr int MinSessionSec = 60;

QJsonObject Cycle::toJson() const {
    return {{"presetId", presetId}, {"name", name}, {"focusSec", focusSec}, {"shortSec", shortSec},
            {"longSec", longSec}, {"every", every}, {"autoBreaks", autoBreaks},
            {"autoFocus", autoFocus}, {"custom", custom}};
}

Cycle Cycle::fromJson(const QJsonObject &o) {
    Cycle c;
    c.presetId = o.value("presetId").toInt();
    c.name = o.value("name").toString();
    c.focusSec = qMax(1, o.value("focusSec").toInt(1500));
    c.shortSec = qMax(1, o.value("shortSec").toInt(300));
    c.longSec = qMax(1, o.value("longSec").toInt(900));
    c.every = qMax(1, o.value("every").toInt(4));
    c.autoBreaks = o.value("autoBreaks").toBool(true);
    c.autoFocus = o.value("autoFocus").toBool(false);
    c.custom = o.value("custom").toBool(false);
    return c;
}

qint64 TimerState::elapsedMs(qint64 now) const {
    if (waiting)
        return 0;
    const qint64 until = pausedAt ? pausedAt : now;
    return qMax<qint64>(0, until - phaseStart - pausedTotal);
}

QJsonObject TimerState::toJson() const {
    return {{"phase", phase}, {"waiting", waiting}, {"round", round}, {"projectId", projectId},
            {"cycle", cycle.toJson()}, {"phaseStart", QString::number(phaseStart)},
            {"pausedAt", QString::number(pausedAt)}, {"pausedTotal", QString::number(pausedTotal)},
            {"sessionId", sessionId}, {"note", note}};
}

TimerState TimerState::fromJson(const QJsonObject &o) {
    TimerState s;
    s.phase = o.value("phase").toString("focus");
    if (s.phase != "focus" && s.phase != "short" && s.phase != "long")
        s.phase = "focus";
    s.waiting = o.value("waiting").toBool(true);
    s.round = qMax(1, o.value("round").toInt(1));
    s.projectId = o.value("projectId").toInt();
    s.cycle = Cycle::fromJson(o.value("cycle").toObject());
    s.phaseStart = o.value("phaseStart").toString().toLongLong();
    s.pausedAt = o.value("pausedAt").toString().toLongLong();
    s.pausedTotal = o.value("pausedTotal").toString().toLongLong();
    s.sessionId = o.value("sessionId").toInt();
    s.note = o.value("note").toString();
    return s;
}

Engine::Engine(Db &db, Clock clock)
    : m_db(db), m_clock(clock ? clock : [] { return QDateTime::currentMSecsSinceEpoch(); }) {}

Cycle Engine::presetCycle(int presetId) const {
    auto rows = m_db.rows("SELECT * FROM presets WHERE id = ?", {presetId});
    if (rows.isEmpty())
        rows = m_db.rows("SELECT * FROM presets ORDER BY sort, id LIMIT 1");
    Cycle c;
    if (rows.isEmpty())
        return c;
    const auto p = rows.first().toMap();
    c.presetId = p.value("id").toInt();
    c.name = p.value("name").toString();
    c.focusSec = qMax(1, p.value("focus_sec").toInt());
    c.shortSec = qMax(1, p.value("short_sec").toInt());
    c.longSec = qMax(1, p.value("long_sec").toInt());
    c.every = qMax(1, p.value("long_every").toInt());
    c.autoBreaks = p.value("auto_breaks").toBool();
    c.autoFocus = p.value("auto_focus").toBool();
    return c;
}

Cycle Engine::projectCycle(int projectId) const {
    return presetCycle(m_db.scalar("SELECT preset_id FROM projects WHERE id = ?", {projectId}, 0).toInt());
}

QString Engine::projectName(int projectId) const {
    return m_db.scalar("SELECT name FROM projects WHERE id = ?", {projectId}).toString();
}

int Engine::validProject(int projectId) const {
    if (projectId && m_db.scalar("SELECT COUNT(*) FROM projects WHERE id = ? AND archived = 0", {projectId}, 0).toInt())
        return projectId;
    return m_db.scalar("SELECT id FROM projects WHERE archived = 0 ORDER BY id LIMIT 1", {}, 0).toInt();
}

TimerState Engine::load() const {
    const auto json = m_db.setting("timer");
    TimerState s;
    if (!json.isEmpty()) {
        s = TimerState::fromJson(QJsonDocument::fromJson(json.toUtf8()).object());
    } else {
        s.projectId = validProject(0);
        s.cycle = projectCycle(s.projectId);
    }
    // A project archived elsewhere can't stay selected while nothing is running.
    if (!s.sessionId && s.projectId != validProject(s.projectId)) {
        s.projectId = validProject(0);
        if (s.idle() && !s.cycle.custom)
            s.cycle = projectCycle(s.projectId);
    }
    // A session deleted from the calendar while running just stops being logged.
    if (s.sessionId && !m_db.scalar("SELECT COUNT(*) FROM sessions WHERE id = ?", {s.sessionId}, 0).toInt())
        s.sessionId = 0;
    return s;
}

void Engine::save(const TimerState &s) const {
    m_db.setSetting("timer", QString::fromUtf8(QJsonDocument(s.toJson()).toJson(QJsonDocument::Compact)));
}

void Engine::openSession(TimerState &s, qint64 startMs) {
    auto q = m_db.exec("INSERT INTO sessions(project_id, started_at, planned_sec, kind, note) VALUES(?, ?, ?, 'focus', ?)",
                       {s.projectId, startMs / 1000, s.cycle.focusSec, s.note});
    s.sessionId = q.lastInsertId().toInt();
}

void Engine::closeSession(TimerState &s, qint64 endMs, bool completed) {
    if (!s.sessionId)
        return;
    const qint64 workedMs = qMax<qint64>(0, endMs - s.phaseStart - s.pausedTotal);
    const int worked = int(workedMs / 1000);
    if (!completed && worked < MinSessionSec)
        m_db.exec("DELETE FROM sessions WHERE id = ?", {s.sessionId});
    else
        m_db.exec("UPDATE sessions SET ended_at = ?, duration_sec = ?, completed = ? WHERE id = ?",
                  {endMs / 1000, worked, completed ? 1 : 0, s.sessionId});
    s.sessionId = 0;
}

void Engine::enter(TimerState &s, const QString &phase, qint64 startMs, bool autoStart) {
    s.phase = phase;
    s.pausedAt = 0;
    s.pausedTotal = 0;
    s.waiting = !autoStart;
    s.phaseStart = autoStart ? startMs : 0;
    if (autoStart && phase == "focus")
        openSession(s, startMs);
}

// Custom times and preset picks last one cycle; then the project's own
// preset (with any edits made since) takes over again.
void Engine::endCycle(TimerState &s) {
    s.round = 1;
    s.cycle = projectCycle(s.projectId);
}

void Engine::advance(TimerState &s, qint64 now, QList<TimerEvent> &events) {
    for (int guard = 0; guard < 200 && s.running() && s.remainingMs(now) <= 0; ++guard) {
        const qint64 endMs = s.phaseStart + s.pausedTotal + qint64(s.lengthSec()) * 1000;
        TimerEvent e;
        e.minutes = (s.lengthSec() + 30) / 60;
        e.project = projectName(s.projectId);
        e.fresh = now - endMs < LateMs;
        e.every = s.cycle.every;
        if (s.phase == "focus") {
            closeSession(s, endMs, true);
            e.type = "focus_done";
            e.next = s.round >= s.cycle.every ? "long" : "short";
            enter(s, e.next, endMs, s.cycle.autoBreaks);
        } else {
            e.type = "break_done";
            if (s.phase == "long")
                endCycle(s);
            else
                ++s.round;
            e.next = "focus";
            enter(s, "focus", endMs, s.cycle.autoFocus && now - endMs < LateMs);
        }
        e.nextStarted = !s.waiting;
        e.nextSec = s.lengthSec();
        e.round = s.round;
        events << e;
    }
}

QList<TimerEvent> Engine::mutate(const std::function<void(TimerState &, qint64)> &change) {
    QList<TimerEvent> events;
    const bool locked = m_db.begin();
    TimerState s = load();
    const qint64 now = m_clock();
    advance(s, now, events);
    if (change)
        change(s, now);
    save(s);
    if (locked)
        m_db.commit();
    return events;
}

QList<TimerEvent> Engine::tick() {
    // Most ticks change nothing: only take the write lock when a phase is due.
    const TimerState s = load();
    if (!s.running() || s.remainingMs(m_clock()) > 0)
        return {};
    return mutate({});
}

QList<TimerEvent> Engine::start() {
    return mutate([this](TimerState &s, qint64 now) {
        if (s.paused()) {
            s.pausedTotal += now - s.pausedAt;
            s.pausedAt = 0;
        } else if (s.waiting) {
            // Pick up edits to the preset made while the timer sat idle.
            if (s.idle() && !s.cycle.custom)
                s.cycle = presetCycle(s.cycle.presetId);
            enter(s, s.phase, now, true);
        }
    });
}

QList<TimerEvent> Engine::pause() {
    return mutate([](TimerState &s, qint64 now) {
        if (s.running())
            s.pausedAt = now;
    });
}

QList<TimerEvent> Engine::toggle() {
    const TimerState s = load();
    return s.running() ? pause() : start();
}

QList<TimerEvent> Engine::skip() {
    return mutate([this](TimerState &s, qint64 now) {
        const qint64 at = s.pausedAt ? s.pausedAt : now;
        if (s.phase == "focus") {
            closeSession(s, at, false);
            enter(s, s.round >= s.cycle.every ? "long" : "short", now, true);
        } else {
            if (s.phase == "long")
                endCycle(s);
            else
                ++s.round;
            enter(s, "focus", now, true);
        }
    });
}

QList<TimerEvent> Engine::stop() {
    return mutate([this](TimerState &s, qint64 now) {
        if (s.phase == "focus" && !s.waiting)
            closeSession(s, s.pausedAt ? s.pausedAt : now, false);
        s.sessionId = 0;
        endCycle(s);
        enter(s, "focus", 0, false);
    });
}

QList<TimerEvent> Engine::setProject(int projectId) {
    return mutate([this, projectId](TimerState &s, qint64) {
        const int id = validProject(projectId);
        if (!id || id != projectId)
            return;
        s.projectId = id;
        if (s.sessionId)
            m_db.exec("UPDATE sessions SET project_id = ? WHERE id = ?", {id, s.sessionId});
        if (s.idle() && !s.cycle.custom)
            s.cycle = projectCycle(id);
    });
}

QList<TimerEvent> Engine::setNote(const QString &note) {
    return mutate([this, note](TimerState &s, qint64) {
        s.note = note.trimmed();
        if (s.sessionId)
            m_db.exec("UPDATE sessions SET note = ? WHERE id = ?", {s.note, s.sessionId});
    });
}

QList<TimerEvent> Engine::usePreset(int presetId) {
    return mutate([this, presetId](TimerState &s, qint64) {
        s.cycle = presetCycle(presetId);
        if (s.sessionId)
            m_db.exec("UPDATE sessions SET planned_sec = ? WHERE id = ?", {s.cycle.focusSec, s.sessionId});
    });
}

QList<TimerEvent> Engine::setCustomCycle(int focusSec, int shortSec, int every) {
    return mutate([this, focusSec, shortSec, every](TimerState &s, qint64) {
        s.cycle.focusSec = qBound(1, focusSec, 24 * 3600);
        s.cycle.shortSec = qBound(1, shortSec, 24 * 3600);
        s.cycle.every = qBound(1, every, 99);
        s.cycle.custom = true;
        s.cycle.name = QCoreApplication::translate("Engine", "Custom");
        if (s.sessionId)
            m_db.exec("UPDATE sessions SET planned_sec = ? WHERE id = ?", {s.cycle.focusSec, s.sessionId});
    });
}

static QString clock(int sec) {
    return QString("%1:%2").arg(sec / 60, 2, 10, QChar('0')).arg(sec % 60, 2, 10, QChar('0'));
}

QString Engine::describe(const TimerEvent &e, QString *body) {
    auto tr = [](const char *s) { return QCoreApplication::translate("Engine", s); };
    QString title, text;
    if (e.type == "focus_done") {
        title = tr("Focus done · %1 min on %2").arg(e.minutes).arg(e.project);
        const QString what = e.next == "long" ? tr("Long break") : tr("Break");
        text = (e.nextStarted ? tr("%1 %2 has started.") : tr("%1 %2 is ready. Press Space to start."))
                   .arg(what, clock(e.nextSec));
    } else {
        title = tr("Break over");
        text = (e.nextStarted ? tr("Focus %1 has started · round %2 of %3.")
                              : tr("Focus %1 is ready · round %2 of %3."))
                   .arg(clock(e.nextSec)).arg(e.round).arg(e.every);
    }
    if (body)
        *body = text;
    return title;
}

void Engine::notify(const QList<TimerEvent> &events, const Db &db) {
    // Only the newest fresh event is worth a notification; older ones
    // happened while nothing was watching.
    for (int i = events.size() - 1; i >= 0; --i) {
        const auto &e = events.at(i);
        if (!e.fresh)
            continue;
        QString body;
        const QString title = describe(e, &body);
        if (!QStandardPaths::findExecutable("notify-send").isEmpty())
            QProcess::startDetached("notify-send", {"-a", "Tomate", "-i", "tomate", title, body});
        if (db.setting("sound", "1") == "1") {
            const QString sound = QString("/usr/share/sounds/freedesktop/stereo/%1.oga")
                                      .arg(e.type == "focus_done" ? "complete" : "bell");
            const QString player = QStandardPaths::findExecutable("pw-play").isEmpty() ? "paplay" : "pw-play";
            if (QFileInfo::exists(sound) && !QStandardPaths::findExecutable(player).isEmpty())
                QProcess::startDetached(player, {sound});
        }
        break;
    }
}
