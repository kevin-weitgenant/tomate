#pragma once

#include <QJsonObject>
#include <QList>
#include <QString>
#include <functional>

class Db;

// The timings in effect for the current cycle: copied from a preset, or set
// by hand for this cycle only (custom).
struct Cycle {
    int presetId = 0;
    QString name;
    int focusSec = 1500;
    int shortSec = 300;
    int longSec = 900;
    int every = 4;
    bool autoBreaks = true;
    bool autoFocus = false;
    bool custom = false;

    bool hasBreaks() const { return shortSec > 0 || longSec > 0; }
    int lengthOf(const QString &phase) const {
        return phase == "focus" ? focusSec : phase == "short" ? shortSec : longSec;
    }
    QJsonObject toJson() const;
    static Cycle fromJson(const QJsonObject &o);
};

// The timer, saved as a few timestamps rather than a ticking counter, so a
// suspend, a crash or a second process can always work out the true state.
struct TimerState {
    QString phase = "focus";   // focus, short or long
    bool waiting = true;       // the phase is ready but not started yet
    int round = 1;             // which focus block of the cycle (1..every)
    int projectId = 0;
    Cycle cycle;
    qint64 phaseStart = 0;     // ms since epoch, when the phase began
    qint64 pausedAt = 0;       // ms since epoch, 0 when not paused
    qint64 pausedTotal = 0;    // ms spent paused in this phase
    int sessionId = 0;         // the open sessions row while focusing
    QString note;

    bool idle() const { return waiting && phase == "focus" && round == 1; }
    bool paused() const { return !waiting && pausedAt != 0; }
    bool running() const { return !waiting && pausedAt == 0; }
    int lengthSec() const { return cycle.lengthOf(phase); }
    qint64 elapsedMs(qint64 now) const;
    qint64 remainingMs(qint64 now) const { return qint64(lengthSec()) * 1000 - elapsedMs(now); }

    QJsonObject toJson() const;
    static TimerState fromJson(const QJsonObject &o);
};

// Something that finished, for a notification and a sound.
struct TimerEvent {
    QString type;          // focus_done or break_done
    QString next;          // the phase that follows
    bool nextStarted = false;
    int minutes = 0;       // length of what finished
    int nextSec = 0;
    int round = 1;
    int every = 4;
    QString project;
    bool fresh = true;     // false when it happened long ago (app was closed)
};

class Engine {
public:
    using Clock = std::function<qint64()>;
    explicit Engine(Db &db, Clock clock = {});

    // tick() catches the saved state up with the clock (writing only when a
    // phase is due) and returns what finished, so the caller can notify;
    // state() then reads it.
    QList<TimerEvent> tick();
    TimerState state() const { return load(); }

    QList<TimerEvent> toggle();
    QList<TimerEvent> start();
    QList<TimerEvent> pause();
    QList<TimerEvent> skip();
    QList<TimerEvent> stop();
    QList<TimerEvent> setProject(int projectId);
    QList<TimerEvent> setNote(const QString &note);
    QList<TimerEvent> usePreset(int presetId);
    QList<TimerEvent> setCustomCycle(int focusSec, int shortSec, int every);

    Cycle presetCycle(int presetId) const;
    Cycle projectCycle(int projectId) const;
    QString projectName(int projectId) const;
    qint64 now() const { return m_clock(); }

    // Sends desktop notifications and plays the sound for fresh events.
    static void notify(const QList<TimerEvent> &events, const Db &db);
    static QString describe(const TimerEvent &e, QString *body = nullptr);

private:
    TimerState load() const;
    void save(const TimerState &s) const;
    void advance(TimerState &s, qint64 now, QList<TimerEvent> &events);
    void enter(TimerState &s, const QString &phase, qint64 startMs, bool autoStart);
    void openSession(TimerState &s, qint64 startMs);
    void closeSession(TimerState &s, qint64 endMs, bool completed);
    void endCycle(TimerState &s);
    QString afterFocus(TimerState &s, qint64 at, qint64 now);
    int validProject(int projectId) const;
    QList<TimerEvent> mutate(const std::function<void(TimerState &, qint64)> &change);

    Db &m_db;
    Clock m_clock;
};
