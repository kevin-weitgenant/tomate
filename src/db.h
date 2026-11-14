#pragma once

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

// The one SQLite file that holds everything: presets, projects, sessions and
// a few settings, including the running timer's state. The GUI, the CLI and
// the bar all read and write it, so it is the single source of truth.
class Db {
public:
    // An empty path means ~/.local/share/tomate/tomate.db.
    explicit Db(const QString &path = {});
    ~Db();
    Db(const Db &) = delete;
    Db &operator=(const Db &) = delete;

    bool ok() const { return m_ok; }
    QString error() const { return m_error; }
    QString path() const { return m_path; }
    QSqlDatabase handle() const;

    static QString defaultPath();

    // Runs a statement with positional bindings; returns the prepared query so
    // callers can step through rows. Errors are printed, never thrown.
    QSqlQuery exec(const QString &sql, const QVariantList &args = {}) const;
    QVariant scalar(const QString &sql, const QVariantList &args = {}, const QVariant &fallback = {}) const;
    QVariantList rows(const QString &sql, const QVariantList &args = {}) const;

    // BEGIN IMMEDIATE takes the write lock up front, so two processes that
    // advance the timer at the same moment can't both act on stale state.
    bool begin() const;
    bool commit() const;
    void rollback() const;

    QString setting(const QString &key, const QString &fallback = {}) const;
    void setSetting(const QString &key, const QString &value) const;

private:
    bool migrate();
    void seed();

    QString m_path;
    QString m_connection;
    bool m_ok = false;
    QString m_error;
};
