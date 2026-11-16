#include "cli.h"

#include "db.h"
#include "desktop.h"
#include "engine.h"

#include <QDate>
#include <QCoreApplication>
#include <QDateTime>
#include <QProcess>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTextStream>
#include <cstdio>

namespace {

const QStringList Commands = {"show", "status", "toggle", "start", "pause", "skip", "stop", "project",
                              "report", "export", "help", "--help", "-h", "--version"};

QTextStream &out() {
    static QTextStream s(stdout);
    return s;
}

int fail(const QString &message) {
    std::fprintf(stderr, "tomate: %s\n", qPrintable(message));
    return 1;
}

QString clock(qint64 sec) {
    sec = qMax<qint64>(0, sec);
    return QString("%1:%2").arg(sec / 60, 2, 10, QChar('0')).arg(sec % 60, 2, 10, QChar('0'));
}

QString hours(qint64 sec) {
    return QString("%1h %2m").arg(sec / 3600).arg((sec % 3600) / 60, 2, 10, QChar('0'));
}

QString phaseName(const QString &phase) {
    return phase == "focus" ? "Focus" : phase == "short" ? "Break" : "Long break";
}

int status(Db &db, Engine &engine, bool json) {
    Engine::notify(engine.tick(), db);
    const TimerState s = engine.state();
    const qint64 now = engine.now();
    const bool over = s.over;
    const qint64 left = over ? (s.elapsedMs(now) + 999) / 1000 : (s.remainingMs(now) + 999) / 1000;
    const QString project = engine.projectName(s.projectId);
    const QString cls = s.idle() ? "idle" : s.waiting ? "ready" : s.paused() ? "paused" : s.phase;
    const QString icon = s.paused() ? "⏸" : s.phase == "focus" ? "◔" : "☕";
    QString text = s.idle() ? QString("◔ %1").arg(project)
                 : s.waiting ? QString("%1 %2 ready").arg(icon, phaseName(s.phase))
                 : over ? QString("%1 +%2 · %3").arg(icon, clock(left), project)
                 : QString("%1 %2 · %3").arg(icon, clock(left), project);
    const QString tooltip = QString("%1 · round %2 of %3 · %4\n%5")
                                .arg(phaseName(s.phase)).arg(s.round).arg(s.cycle.every)
                                .arg(s.cycle.custom ? "Custom" : s.cycle.name, project);
    if (!json) {
        out() << text << "\n";
        return 0;
    }
    const int pct = s.lengthSec() ? int(100 * s.elapsedMs(now) / (qint64(s.lengthSec()) * 1000)) : 0;
    // Today's closed sessions plus the block running right now.
    const qint64 dayStart = QDate::currentDate().startOfDay().toSecsSinceEpoch();
    qint64 today = db.scalar("SELECT COALESCE(SUM(duration_sec), 0) FROM sessions WHERE started_at >= ? AND ended_at IS NOT NULL",
                             {dayStart}, 0).toLongLong();
    if (s.sessionId)
        today += s.elapsedMs(now) / 1000;
    const QString ends = s.running() && !over ? QDateTime::fromMSecsSinceEpoch(now + s.remainingMs(now)).toString("HH:mm") : QString();
    QJsonObject o{{"text", text}, {"tooltip", tooltip}, {"class", cls}, {"alt", cls},
                  {"percentage", qBound(0, pct, 100)}, {"phase", s.phase}, {"remaining", left},
                  {"round", s.round}, {"every", s.cycle.every}, {"project", project},
                  {"paused", s.paused()}, {"waiting", s.waiting}, {"idle", s.idle()}, {"ends", ends}, {"over", over},
                  {"breaks", s.cycle.hasBreaks()},
                  {"note", s.note}, {"length", s.lengthSec()}, {"today", today},
                  {"goal", db.setting("daily_goal_min", "240").toInt() * 60},
                  {"cycle", s.cycle.custom ? QString("Custom") : s.cycle.name},
                  {"color", db.scalar("SELECT color FROM projects WHERE id = ?", {s.projectId}, 0).toInt()}};
    out() << QJsonDocument(o).toJson(QJsonDocument::Compact) << "\n";
    return 0;
}

int report(Db &db, const QStringList &args, bool json) {
    const QDate today = QDate::currentDate();
    QDate from = today, to = today.addDays(1);
    QString label = "Today";
    if (args.contains("--week")) {
        from = today.addDays(1 - today.dayOfWeek());
        to = from.addDays(7);
        label = "This week";
    } else if (args.contains("--month")) {
        from = QDate(today.year(), today.month(), 1);
        to = from.addMonths(1);
        label = "This month";
    }
    const auto rows = db.rows("SELECT p.name, SUM(s.duration_sec) AS sec, COUNT(*) AS n FROM sessions s "
                              "JOIN projects p ON p.id = s.project_id "
                              "WHERE s.started_at >= ? AND s.started_at < ? AND s.ended_at IS NOT NULL "
                              "GROUP BY p.id ORDER BY sec DESC",
                              {from.startOfDay().toSecsSinceEpoch(), to.startOfDay().toSecsSinceEpoch()});
    qint64 total = 0;
    QJsonArray projects;
    for (const auto &r : rows) {
        const auto m = r.toMap();
        total += m.value("sec").toLongLong();
        projects << QJsonObject{{"project", m.value("name").toString()}, {"seconds", m.value("sec").toLongLong()},
                                {"sessions", m.value("n").toInt()}};
    }
    if (json) {
        out() << QJsonDocument(QJsonObject{{"from", from.toString(Qt::ISODate)},
                                           {"to", to.addDays(-1).toString(Qt::ISODate)},
                                           {"seconds", total}, {"projects", projects}})
                     .toJson(QJsonDocument::Compact) << "\n";
        return 0;
    }
    out() << label << ": " << hours(total) << "\n";
    for (const auto &p : projects) {
        const auto o = p.toObject();
        out() << "  " << hours(o.value("seconds").toInteger()).rightJustified(8) << "  " << o.value("project").toString()
              << " (" << o.value("sessions").toInt() << ")\n";
    }
    return 0;
}

QString csv(QString v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n'))
        v = '"' + v.replace("\"", "\"\"") + '"';
    return v;
}

int exportCsv(Db &db, const QStringList &args) {
    auto dateArg = [&](const QString &flag, const QDate &fallback) {
        const int i = args.indexOf(flag);
        return i >= 0 && i + 1 < args.size() ? QDate::fromString(args.at(i + 1), Qt::ISODate) : fallback;
    };
    const QDate from = dateArg("--from", QDate(1970, 1, 1));
    const QDate to = dateArg("--to", QDate(9999, 12, 31));
    if (!from.isValid() || !to.isValid())
        return fail("dates must look like 2026-11-01");
    out() << "date,start,end,minutes,project,kind,completed,note\n";
    for (const auto &r : db.rows("SELECT s.*, p.name AS project FROM sessions s JOIN projects p ON p.id = s.project_id "
                                 "WHERE s.started_at >= ? AND s.started_at < ? AND s.ended_at IS NOT NULL "
                                 "ORDER BY s.started_at",
                                 {from.startOfDay().toSecsSinceEpoch(), to.addDays(1).startOfDay().toSecsSinceEpoch()})) {
        const auto m = r.toMap();
        const auto a = QDateTime::fromSecsSinceEpoch(m.value("started_at").toLongLong());
        const auto b = QDateTime::fromSecsSinceEpoch(m.value("ended_at").toLongLong());
        out() << a.date().toString(Qt::ISODate) << "," << a.time().toString("HH:mm") << ","
              << b.time().toString("HH:mm") << "," << m.value("duration_sec").toInt() / 60 << ","
              << csv(m.value("project").toString()) << "," << m.value("kind").toString() << ","
              << (m.value("completed").toBool() ? "yes" : "no") << "," << csv(m.value("note").toString()) << "\n";
    }
    return 0;
}

void help() {
    out() << "Usage: tomate [command]\n\n"
             "  (none), open        open the window (or bring it here)\n"
             "  show                bring the window to this workspace, opening it if needed\n"
             "  status [--json]     what the timer is doing (for the bar)\n"
             "  toggle              start or pause\n"
             "  start | pause | skip\n"
             "  stop [--discard]    stop; --discard drops the partial block\n"
             "  project <name>      switch the timer to a project\n"
             "  report [--today|--week|--month] [--json]\n"
             "  export --csv [--from YYYY-MM-DD] [--to YYYY-MM-DD]\n\n"
             "Data: " << Db::defaultPath() << "\n";
}

} // namespace

bool Cli::handles(const QStringList &args) {
    return args.size() > 1 && Commands.contains(args.at(1));
}

int Cli::run(const QStringList &args) {
    const QString cmd = args.value(1);
    if (cmd == "help" || cmd == "--help" || cmd == "-h") {
        help();
        return 0;
    }
    if (cmd == "--version") {
        out() << "tomate 0.1.0\n";
        return 0;
    }
    if (cmd == "show") {
        if (Desktop::summon(Desktop::windowAddress()))
            return 0;
        // Not open yet: start the window as its own process and return.
        return QProcess::startDetached(QCoreApplication::applicationFilePath(), {}) ? 0 : fail("could not start the window");
    }
    Db db;
    if (!db.ok())
        return fail("can't open " + db.path() + ": " + db.error());
    Engine engine(db);
    const bool json = args.contains("--json");

    if (cmd == "status")
        return status(db, engine, json);
    if (cmd == "report")
        return report(db, args, json);
    if (cmd == "export") {
        if (!args.contains("--csv"))
            return fail("export needs --csv");
        return exportCsv(db, args);
    }
    if (cmd == "project") {
        const QString name = args.mid(2).filter(QRegularExpression("^[^-]")).join(' ');
        const int id = db.scalar("SELECT id FROM projects WHERE archived = 0 AND name LIKE ? ORDER BY id LIMIT 1",
                                 {name}, 0).toInt();
        if (!id)
            return fail("no project called \"" + name + "\"");
        Engine::notify(engine.setProject(id), db);
        return status(db, engine, json);
    }
    QList<TimerEvent> events = cmd == "toggle" ? engine.toggle()
                             : cmd == "start"  ? engine.start()
                             : cmd == "pause"  ? engine.pause()
                             : cmd == "skip"   ? engine.skip()
                                               : engine.stop(args.contains("--discard"));
    Engine::notify(events, db);
    return status(db, engine, json);
}
