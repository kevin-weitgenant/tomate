#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

#include "db.h"
#include "engine.h"
#include "theme.h"
#include "translator.h"

static constexpr qint64 Min = 60 * 1000;

// A database in a temp dir and a clock the test moves by hand.
struct Rig {
    QTemporaryDir dir;
    qint64 now = 1'800'000'000'000;
    Db db{dir.filePath("t.db")};
    Engine engine{db, [this] { return now; }};

    int sessions(const QString &where = "1") {
        return db.scalar("SELECT COUNT(*) FROM sessions WHERE " + where, {}, 0).toInt();
    }
    QVariantMap session(int id) { return db.rows("SELECT * FROM sessions WHERE id = ?", {id}).value(0).toMap(); }
    void usePreset(const QString &name) {
        engine.usePreset(db.scalar("SELECT id FROM presets WHERE name = ?", {name}).toInt());
    }
};

class TomateTests : public QObject {
    Q_OBJECT

private slots:
    void seedsPresetsAndAProject() {
        Rig r;
        QVERIFY(r.db.ok());
        QCOMPARE(r.db.scalar("SELECT COUNT(*) FROM presets").toInt(), 4);
        const auto s = r.engine.state();
        QVERIFY(s.idle());
        QCOMPARE(s.cycle.name, QString("Classic"));
        QCOMPARE(s.remainingMs(r.now), 25 * Min);
    }

    void focusEndsIntoAnAutomaticBreak() {
        Rig r;
        r.usePreset("Deep");               // 50 / 10 / 20 every 3, breaks start on their own
        r.engine.start();
        r.now += 50 * Min;
        const auto events = r.engine.tick();
        QCOMPARE(events.size(), 1);
        QCOMPARE(events.first().type, QString("focus_done"));
        QVERIFY(events.first().nextStarted);
        const auto s = r.engine.state();
        QCOMPARE(s.phase, QString("short"));
        QVERIFY(s.running());
        QCOMPARE(r.sessions("completed = 1 AND duration_sec = 3000"), 1);

        // Break over: the next focus waits, because auto focus is off.
        r.now += 10 * Min;
        r.engine.tick();
        QCOMPARE(r.engine.state().phase, QString("focus"));
        QVERIFY(r.engine.state().waiting);
        QCOMPARE(r.engine.state().round, 2);
    }

    void longBreakComesAfterTheLastRound() {
        Rig r;
        r.engine.setCustomCycle(10 * 60, 2 * 60, 2);
        for (int i = 0; i < 2; ++i) {
            r.engine.start();
            r.now += 10 * Min;
            r.engine.tick();
            if (i == 0) {
                r.now += 2 * Min;
                r.engine.tick();
            }
        }
        QCOMPARE(r.engine.state().phase, QString("long"));
        QCOMPARE(r.sessions(), 2);
    }

    void customTimesLastOneCycle() {
        Rig r;
        r.engine.setCustomCycle(40 * 60, 8 * 60, 1);
        QVERIFY(r.engine.state().cycle.custom);
        r.engine.start();
        r.now += 40 * Min;
        r.engine.tick();                   // into the long break (every = 1)
        QCOMPARE(r.engine.state().phase, QString("long"));
        r.now += 15 * Min;                 // Classic's long break length is kept
        r.engine.tick();
        const auto s = r.engine.state();
        QVERIFY(!s.cycle.custom);
        QCOMPARE(s.cycle.focusSec, 1500);
        QCOMPARE(s.round, 1);
    }

    void customTimesApplyToTheRunningBlock() {
        Rig r;
        r.engine.start();
        r.now += 10 * Min;
        r.engine.setCustomCycle(12 * 60, 3 * 60, 4);
        QCOMPARE(r.engine.state().remainingMs(r.now), 2 * Min);
    }

    void suspendDoesNotFreezeTheClock() {
        Rig r;
        r.engine.start();
        r.now += 5 * Min;                  // the laptop slept; nothing ticked
        QCOMPARE(r.engine.state().remainingMs(r.now), 20 * Min);
    }

    void pausedTimeIsNotWork() {
        Rig r;
        r.engine.start();
        r.now += 5 * Min;
        r.engine.pause();
        r.now += 30 * Min;
        QCOMPARE(r.engine.state().remainingMs(r.now), 20 * Min);
        r.engine.start();
        r.now += 20 * Min;
        r.engine.tick();
        QCOMPARE(r.sessions("completed = 1 AND duration_sec = 1500"), 1);
    }

    void stoppingEarlyKeepsRealMinutes() {
        Rig r;
        r.engine.start();
        r.now += 18 * Min;
        r.engine.stop();
        QCOMPARE(r.sessions("completed = 0 AND duration_sec = 1080 AND ended_at IS NOT NULL"), 1);
        QVERIFY(r.engine.state().idle());
    }

    void aFalseStartLeavesNoBlock() {
        Rig r;
        r.engine.start();
        r.now += 30 * 1000;
        r.engine.stop();
        QCOMPARE(r.sessions(), 0);
    }

    void lateFocusWaitsInsteadOfInventingWork() {
        Rig r;
        r.usePreset("Sprint");
        const int id = r.db.scalar("SELECT id FROM presets WHERE name = 'Sprint'").toInt();
        r.db.exec("UPDATE presets SET auto_focus = 1 WHERE id = ?", {id});
        r.engine.usePreset(id);
        r.engine.start();
        r.now += 3 * 60 * Min;             // the app was closed for three hours
        const auto events = r.engine.tick();
        QCOMPARE(r.sessions(), 1);
        QVERIFY(r.engine.state().waiting);
        for (const auto &e : events)
            QVERIFY(!e.fresh);
    }

    void aSecondProcessSeesTheSameTimer() {
        Rig r;
        r.engine.start();
        r.now += 7 * Min;
        Engine other(r.db, [&r] { return r.now; });
        QCOMPARE(other.state().remainingMs(r.now), 18 * Min);
        other.pause();
        QVERIFY(r.engine.state().paused());
    }

    void switchingProjectMovesTheRunningBlock() {
        Rig r;
        r.db.exec("INSERT INTO projects(name, color, preset_id, created_at) VALUES('Side', 1, 2, 0)");
        const int side = r.db.scalar("SELECT id FROM projects WHERE name = 'Side'").toInt();
        r.engine.start();
        r.engine.setProject(side);
        r.engine.setNote("refactor");
        const auto row = r.session(r.engine.state().sessionId);
        QCOMPARE(row.value("project_id").toInt(), side);
        QCOMPARE(row.value("note").toString(), QString("refactor"));
    }

    void skipEndsFocusAndStartsTheBreak() {
        Rig r;
        r.engine.start();
        r.now += 20 * Min;
        r.engine.skip();
        const auto s = r.engine.state();
        QCOMPARE(s.phase, QString("short"));
        QVERIFY(s.running());
        QCOMPARE(r.sessions("duration_sec = 1200"), 1);
        r.engine.skip();
        QCOMPARE(r.engine.state().phase, QString("focus"));
        QVERIFY(r.engine.state().running());
        QCOMPARE(r.engine.state().round, 2);
    }

    void focusOnlyEndsWithoutABreak() {
        Rig r;
        r.usePreset("Focus only");             // 50 minutes, no breaks
        QVERIFY(!r.engine.state().cycle.hasBreaks());
        r.engine.start();
        r.now += 50 * Min;
        const auto events = r.engine.tick();
        QCOMPARE(events.size(), 1);
        QCOMPARE(events.first().type, QString("focus_done"));
        QCOMPARE(events.first().next, QString("focus"));
        QVERIFY(!events.first().nextStarted);
        const auto s = r.engine.state();
        QVERIFY(s.idle());                     // back to ready, no break timer
        QCOMPARE(r.sessions("completed = 1 AND duration_sec = 3000"), 1);
        // Nothing more happens however long you wait.
        r.now += 3 * 60 * Min;
        QVERIFY(r.engine.tick().isEmpty());
        QCOMPARE(r.sessions(), 1);
    }

    void focusOnlyCanChainBlocks() {
        Rig r;
        const int id = r.db.scalar("SELECT id FROM presets WHERE name = 'Focus only'").toInt();
        r.db.exec("UPDATE presets SET auto_focus = 1 WHERE id = ?", {id});
        r.engine.usePreset(id);
        r.engine.start();
        r.now += 50 * Min;
        r.engine.tick();
        QVERIFY(r.engine.state().running());
        QCOMPARE(r.engine.state().phase, QString("focus"));
        QCOMPARE(r.sessions(), 2);             // the finished one and the new one
    }

    void aZeroShortBreakStillKeepsTheLongOne() {
        Rig r;
        r.engine.setCustomCycle(10 * 60, 0, 2); // long break stays Classic's 15
        r.engine.start();
        r.now += 10 * Min;
        r.engine.tick();
        QCOMPARE(r.engine.state().phase, QString("focus"));
        QCOMPARE(r.engine.state().round, 2);
        r.engine.start();
        r.now += 10 * Min;
        r.engine.tick();
        QCOMPARE(r.engine.state().phase, QString("long"));
    }

    void skipWithNoBreakStartsTheNextBlock() {
        Rig r;
        r.usePreset("Focus only");
        r.engine.start();
        r.now += 20 * Min;
        r.engine.skip();
        QVERIFY(r.engine.state().running());
        QCOMPARE(r.engine.state().phase, QString("focus"));
        QCOMPARE(r.sessions("duration_sec = 1200"), 1);
    }

    void themeReadsThePalette() {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        write(dir.path() + "/theme/colors.toml", "mode = \"light\"\naccent = \"#112233\"\ngreen = \"#00ff00\"\n");
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.colors().value("green").toString(), QString("#00ff00"));
        QVERIFY(!theme.dark());
        QCOMPARE(theme.projectColors().size(), Theme::projectSlots().size());
    }

    void themeFallsBack() {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#7aa2f7"));
        QVERIFY(theme.dark());
    }

    void translatorFallsBackToEnglish() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

private:
    static void write(const QString &path, const QByteArray &contents) {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }
};

QTEST_MAIN(TomateTests)
#include "tomate_tests.moc"
