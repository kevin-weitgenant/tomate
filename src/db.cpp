#include "db.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QSqlError>
#include <QSqlRecord>
#include <QStandardPaths>
#include <QUuid>
#include <cstdio>

QString Db::defaultPath() {
    // Lets tests and experiments use a throwaway database.
    if (!qEnvironmentVariableIsEmpty("TOMATE_DB"))
        return qEnvironmentVariable("TOMATE_DB");
    QString base = qEnvironmentVariable("XDG_DATA_HOME");
    if (base.isEmpty())
        base = QDir::homePath() + "/.local/share";
    return base + "/tomate/tomate.db";
}

Db::Db(const QString &path)
    : m_path(path.isEmpty() ? defaultPath() : path),
      m_connection("tomate-" + QUuid::createUuid().toString(QUuid::WithoutBraces)) {
    QDir().mkpath(QFileInfo(m_path).absolutePath());
    auto db = QSqlDatabase::addDatabase("QSQLITE", m_connection);
    db.setDatabaseName(m_path);
    db.setConnectOptions("QSQLITE_BUSY_TIMEOUT=3000");
    if (!db.open()) {
        m_error = db.lastError().text();
        return;
    }
    // WAL lets the bar read while the window writes.
    exec("PRAGMA journal_mode=WAL");
    exec("PRAGMA foreign_keys=ON");
    m_ok = migrate();
}

Db::~Db() {
    {
        auto db = QSqlDatabase::database(m_connection, false);
        if (db.isOpen())
            db.close();
    }
    QSqlDatabase::removeDatabase(m_connection);
}

QSqlDatabase Db::handle() const { return QSqlDatabase::database(m_connection, false); }

QSqlQuery Db::exec(const QString &sql, const QVariantList &args) const {
    QSqlQuery q(handle());
    q.prepare(sql);
    // A null QString would bind as SQL NULL; text columns want "" instead.
    for (const auto &a : args)
        q.addBindValue(a.typeId() == QMetaType::QString && a.toString().isNull() ? QVariant(QString("")) : a);
    if (!q.exec())
        std::fprintf(stderr, "tomate: sql error: %s\n  in: %s\n", qPrintable(q.lastError().text()), qPrintable(sql));
    return q;
}

QVariant Db::scalar(const QString &sql, const QVariantList &args, const QVariant &fallback) const {
    auto q = exec(sql, args);
    if (q.next() && !q.value(0).isNull())
        return q.value(0);
    return fallback;
}

QVariantList Db::rows(const QString &sql, const QVariantList &args) const {
    QVariantList out;
    auto q = exec(sql, args);
    while (q.next()) {
        QVariantMap row;
        const auto rec = q.record();
        for (int i = 0; i < rec.count(); ++i)
            row.insert(rec.fieldName(i), q.value(i));
        out << row;
    }
    return out;
}

bool Db::begin() const {
    QSqlQuery q(handle());
    return q.exec("BEGIN IMMEDIATE");
}
bool Db::commit() const {
    QSqlQuery q(handle());
    return q.exec("COMMIT");
}
void Db::rollback() const {
    QSqlQuery q(handle());
    q.exec("ROLLBACK");
}

QString Db::setting(const QString &key, const QString &fallback) const {
    return scalar("SELECT value FROM settings WHERE key = ?", {key}, fallback).toString();
}

void Db::setSetting(const QString &key, const QString &value) const {
    exec("INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
         {key, value});
}

// Each entry moves the schema up one version; never edit a shipped entry,
// append a new one, so existing databases upgrade in place.
bool Db::migrate() {
    const QStringList steps = {
        R"(CREATE TABLE presets(
             id INTEGER PRIMARY KEY,
             name TEXT NOT NULL,
             focus_sec INTEGER NOT NULL,
             short_sec INTEGER NOT NULL,
             long_sec INTEGER NOT NULL,
             long_every INTEGER NOT NULL,
             auto_breaks INTEGER NOT NULL DEFAULT 1,
             auto_focus INTEGER NOT NULL DEFAULT 0,
             sort INTEGER NOT NULL DEFAULT 0);
           CREATE TABLE projects(
             id INTEGER PRIMARY KEY,
             name TEXT NOT NULL,
             color INTEGER NOT NULL DEFAULT 0,
             preset_id INTEGER REFERENCES presets(id) ON DELETE SET NULL,
             archived INTEGER NOT NULL DEFAULT 0,
             created_at INTEGER NOT NULL);
           CREATE TABLE sessions(
             id INTEGER PRIMARY KEY,
             project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
             started_at INTEGER NOT NULL,
             ended_at INTEGER,
             duration_sec INTEGER NOT NULL DEFAULT 0,
             planned_sec INTEGER NOT NULL DEFAULT 0,
             kind TEXT NOT NULL DEFAULT 'focus',
             completed INTEGER NOT NULL DEFAULT 0,
             note TEXT NOT NULL DEFAULT '');
           CREATE INDEX sessions_started ON sessions(started_at);
           CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);)",
        // A preset for focusing without breaks: a block ends and that's it.
        R"(INSERT INTO presets(name, focus_sec, short_sec, long_sec, long_every, auto_breaks, auto_focus, sort)
           VALUES('Focus only', 3000, 0, 0, 1, 0, 0, (SELECT COALESCE(MAX(sort), 0) + 1 FROM presets));)",
    };

    int version = scalar("PRAGMA user_version", {}, 0).toInt();
    for (int v = version; v < steps.size(); ++v) {
        if (!begin()) {
            m_error = "Could not lock the database";
            return false;
        }
        for (const auto &statement : steps[v].split(';', Qt::SkipEmptyParts)) {
            if (statement.trimmed().isEmpty())
                continue;
            QSqlQuery q(handle());
            if (!q.exec(statement)) {
                m_error = q.lastError().text();
                rollback();
                return false;
            }
        }
        exec(QString("PRAGMA user_version = %1").arg(v + 1));
        if (v == 0)
            seed();
        commit();
    }
    return true;
}

void Db::seed() {
    exec("INSERT INTO presets(name, focus_sec, short_sec, long_sec, long_every, auto_breaks, auto_focus, sort) VALUES"
         "('Classic', 1500, 300, 900, 4, 1, 0, 0),"
         "('Deep', 3000, 600, 1200, 3, 1, 0, 1),"
         "('Sprint', 900, 180, 600, 4, 1, 0, 2)");
    exec("INSERT INTO projects(name, color, preset_id, created_at) VALUES('General', 0, 1, ?)",
         {QDateTime::currentSecsSinceEpoch()});
    setSetting("daily_goal_min", "240");
    setSetting("sound", "1");
}
