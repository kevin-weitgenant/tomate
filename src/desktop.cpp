#include "desktop.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>

namespace {

QByteArray hyprctl(const QStringList &args) {
    if (QStandardPaths::findExecutable("hyprctl").isEmpty() || qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE"))
        return {};
    QProcess p;
    p.start("hyprctl", args);
    if (!p.waitForFinished(1500))
        p.kill();
    return p.readAllStandardOutput();
}

void dispatch(const QString &lua) { hyprctl({"dispatch", lua}); }

QJsonObject client(const QString &address) {
    for (const auto &v : QJsonDocument::fromJson(hyprctl({"clients", "-j"})).array())
        if (v.toObject().value("address").toString() == address)
            return v.toObject();
    return {};
}

} // namespace

QString Desktop::windowAddress(qint64 pid) {
    for (const auto &v : QJsonDocument::fromJson(hyprctl({"clients", "-j"})).array()) {
        const auto c = v.toObject();
        // The class, exactly: a browser tab titled "Tomate" is not the app.
        if (c.value("class").toString() == "tomate" && (!pid || c.value("pid").toInteger() == pid))
            return c.value("address").toString();
    }
    return {};
}

bool Desktop::summon(const QString &address) {
    if (address.isEmpty())
        return false;
    const auto here = QJsonDocument::fromJson(hyprctl({"activeworkspace", "-j"})).object().value("name").toString();
    if (here.isEmpty())
        return false;
    const auto c = client(address);
    if (c.value("workspace").toObject().value("name").toString() != here) {
        dispatch(QString(R"(hl.dsp.window.move({ workspace = "%1", follow = true, window = "address:%2" }))")
                     .arg(here, address));
        // Omarchy's dock remembers where a minimized window came from; it is
        // back now, so forget that.
        for (const auto &t : c.value("tags").toArray())
            if (t.toString().startsWith("omarchy-minimized-from-"))
                dispatch(QString(R"(hl.dsp.window.tag({ tag = "-%1", window = "address:%2" }))").arg(t.toString(), address));
    }
    dispatch(QString(R"(hl.dsp.focus({ window = "address:%1" }))").arg(address));
    return true;
}
