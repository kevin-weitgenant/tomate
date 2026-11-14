// tomate — a Pomodoro timer that keeps a diary: pick a project, focus, take
// breaks, and see on a calendar when the work happened.

#include <QCoreApplication>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>

#include "backend.h"
#include "cli.h"
#include "db.h"
#include "desktop.h"
#include "engine.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    QStringList args;
    for (int i = 0; i < argc; ++i)
        args << QString::fromLocal8Bit(argv[i]);

    // The bar runs `tomate status --json` every second, so CLI commands start
    // a bare core application: no display, no QML, fast.
    if (Cli::handles(args)) {
        QCoreApplication app(argc, argv);
        app.setApplicationName("tomate");
        Translator translator;
        app.installTranslator(&translator);
        return Cli::run(args);
    }

    // One window only: opening Tomate again (launcher, bar, terminal) brings
    // the open one to the workspace in view instead of starting another.
    if (args.size() < 2 || args.at(1) == "open") {
        if (const QString open = Desktop::windowAddress(); !open.isEmpty() && qEnvironmentVariableIsEmpty("TOMATE_SHOTS")) {
            QCoreApplication probe(argc, argv);
            Desktop::summon(open);
            return 0;
        }
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("tomate");
    app.setApplicationVersion("0.1.0");

    // Matches the window to tomate.desktop, so the compositor (Wayland app_id)
    // and the launcher pick up the installed icon.
    app.setDesktopFileName("tomate");
    app.setWindowIcon(QIcon::fromTheme("tomate"));

    // Omarchy points the monospace alias at the desktop font; use it
    // everywhere so the app reads like the rest of the desktop.
    QFont font = QFontDatabase::systemFont(QFontDatabase::FixedFont);
    font.setPointSizeF(10.5);
    app.setFont(font);

    QQuickStyle::setStyle("Material");

    Translator translator;
    app.installTranslator(&translator);

    // Declared before the QML engine so they outlive it: QML bindings must
    // never see them gone while the window tears down.
    Db db;
    Theme theme;
    Engine timer(db);
    Backend backend(db, timer);
    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("dbError", db.ok() ? QString() : db.path() + ": " + db.error());

    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("screenshotMode", !qEnvironmentVariableIsEmpty("TOMATE_SHOTS"));
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    // Development aid: TOMATE_SHOTS=<dir> saves each screen as a PNG and
    // quits, so the UI can be checked offscreen and the README screenshots
    // regenerated (bin/screenshots).
    if (const QString shots = qEnvironmentVariable("TOMATE_SHOTS"); !shots.isEmpty()) {
        struct Shot { int page; int key; const char *name; };
        static const QList<Shot> plan = {
            {0, 0, "timer"}, {1, 0, "calendar-week"}, {1, Qt::Key_M, "calendar-month"},
            {2, 0, "projects"}, {3, 0, "presets"}, {0, Qt::Key_E, "custom-cycle"},
        };
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        // Park the pointer off the rail, so no hover hints show in the shots.
        QCoreApplication::postEvent(window, new QMouseEvent(QEvent::MouseMove, QPointF(window->width() - 2, window->height() - 2),
                                                            QPointF(window->width() - 2, window->height() - 2),
                                                            Qt::NoButton, Qt::NoButton, Qt::NoModifier));
        auto *step = new QTimer(&app);
        auto *index = new int(-1);
        QObject::connect(step, &QTimer::timeout, &app, [=, &app] {
            if (*index >= 0)
                window->grabWindow().save(QString("%1/%2.png").arg(shots, plan.at(*index).name));
            if (++*index == plan.size()) {
                app.quit();
                return;
            }
            const Shot &s = plan.at(*index);
            window->setProperty("page", s.page);
            if (s.key)
                for (auto type : {QEvent::KeyPress, QEvent::KeyRelease})
                    QCoreApplication::postEvent(window, new QKeyEvent(type, s.key, Qt::NoModifier, QKeySequence(s.key).toString().toLower()));
        });
        step->start(800);
    }

    return app.exec();
}
