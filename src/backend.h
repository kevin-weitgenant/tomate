#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include "engine.h"

class Db;

// Everything QML sees: the live timer, projects, presets, sessions for the
// calendar, and the actions behind every button and key.
class Backend : public QObject {
    Q_OBJECT
    // Timer, refreshed on every tick.
    Q_PROPERTY(QString phase READ phase NOTIFY ticked)
    Q_PROPERTY(bool waiting READ waiting NOTIFY ticked)
    Q_PROPERTY(bool paused READ paused NOTIFY ticked)
    Q_PROPERTY(bool running READ running NOTIFY ticked)
    Q_PROPERTY(bool idle READ idle NOTIFY ticked)
    Q_PROPERTY(int remainingSec READ remainingSec NOTIFY ticked)
    Q_PROPERTY(int lengthSec READ lengthSec NOTIFY ticked)
    Q_PROPERTY(int workedSec READ workedSec NOTIFY ticked)
    Q_PROPERTY(double progress READ progress NOTIFY ticked)
    Q_PROPERTY(int round READ round NOTIFY ticked)
    Q_PROPERTY(int every READ every NOTIFY ticked)
    Q_PROPERTY(int projectId READ projectId NOTIFY ticked)
    Q_PROPERTY(QString note READ note NOTIFY ticked)
    Q_PROPERTY(QVariantMap cycle READ cycle NOTIFY ticked)
    Q_PROPERTY(double endsAt READ endsAt NOTIFY ticked)
    Q_PROPERTY(int todaySec READ todaySec NOTIFY ticked)
    Q_PROPERTY(QVariantList todayByProject READ todayByProject NOTIFY ticked)
    Q_PROPERTY(double nowSec READ nowSec NOTIFY ticked)
    // Stored data, refreshed when it changes.
    Q_PROPERTY(QVariantList projects READ projects NOTIFY dataChanged)
    Q_PROPERTY(QVariantList presets READ presets NOTIFY dataChanged)
    Q_PROPERTY(int dailyGoalMin READ dailyGoalMin NOTIFY dataChanged)
    Q_PROPERTY(bool sound READ sound NOTIFY dataChanged)
    Q_PROPERTY(int revision READ revision NOTIFY dataChanged)
    Q_PROPERTY(QString dbPath READ dbPath CONSTANT)

public:
    Backend(Db &db, Engine &engine, QObject *parent = nullptr);

    QString phase() const { return m_state.phase; }
    bool waiting() const { return m_state.waiting; }
    bool paused() const { return m_state.paused(); }
    bool running() const { return m_state.running(); }
    bool idle() const { return m_state.idle(); }
    int remainingSec() const;
    int lengthSec() const { return m_state.lengthSec(); }
    // Seconds worked in the open focus block (for the stop prompt).
    int workedSec() const { return m_state.phase == "focus" && m_state.sessionId ? int(m_state.elapsedMs(m_now) / 1000) : 0; }
    double progress() const;
    int round() const { return m_state.round; }
    int every() const { return m_state.cycle.every; }
    int projectId() const { return m_state.projectId; }
    QString note() const { return m_state.note; }
    QVariantMap cycle() const;
    double endsAt() const;
    int todaySec() const { return m_todaySec; }
    QVariantList todayByProject() const { return m_todayByProject; }
    double nowSec() const { return m_now / 1000.0; }

    QVariantList projects() const { return m_projects; }
    QVariantList presets() const { return m_presets; }
    int dailyGoalMin() const;
    bool sound() const;
    int revision() const { return m_revision; }
    QString dbPath() const;

    // Timer
    Q_INVOKABLE void toggle();
    Q_INVOKABLE void skip();
    Q_INVOKABLE void stop(bool discard = false);
    Q_INVOKABLE void setProject(int id);
    Q_INVOKABLE void setNote(const QString &note);
    Q_INVOKABLE void usePreset(int id);
    Q_INVOKABLE void setCustomCycle(int focusMin, int breakMin, int rounds);
    Q_INVOKABLE int saveCycleAsPreset(const QString &name);

    // Projects
    Q_INVOKABLE int createProject(const QString &name, int color, int presetId);
    Q_INVOKABLE void updateProject(int id, const QString &name, int color, int presetId);
    Q_INVOKABLE void setArchived(int id, bool archived);
    Q_INVOKABLE void deleteProject(int id);

    // Presets: a map with name, focusMin, shortMin, longMin, every, autoBreaks, autoFocus.
    Q_INVOKABLE int createPreset(const QVariantMap &p);
    Q_INVOKABLE void updatePreset(int id, const QVariantMap &p);
    Q_INVOKABLE bool deletePreset(int id);

    // Sessions, in seconds since the epoch.
    Q_INVOKABLE QVariantList sessions(double fromSec, double toSec) const;
    Q_INVOKABLE QVariantList dayTotals(double fromSec, int days) const;
    Q_INVOKABLE int addSession(int projectId, double startSec, double endSec, const QString &note);
    Q_INVOKABLE void updateSession(int id, int projectId, double startSec, double endSec, const QString &note);
    Q_INVOKABLE void deleteSession(int id);

    // Settings
    Q_INVOKABLE void setDailyGoalMin(int minutes);
    Q_INVOKABLE void setSound(bool on);

signals:
    void ticked();
    void dataChanged();

private:
    void refresh();
    void after(const QList<TimerEvent> &events);
    void reloadData();
    int runningSec() const;

    Db &m_db;
    Engine &m_engine;
    QTimer m_timer;
    TimerState m_state;
    qint64 m_now = 0;
    int m_todaySec = 0;
    QVariantList m_todayByProject;
    QVariantList m_projects, m_presets;
    int m_revision = 0;
    int m_lastSessionCount = -1;
    QString m_lastStateJson;
};
