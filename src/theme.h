#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

// Follows the current Omarchy theme live: the accent, the whole palette from
// colors.toml (so the window and project colours match the desktop), the
// light/dark mode, and Hyprland's window rounding.
class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString accent READ accent NOTIFY changed)
    Q_PROPERTY(QString accentForeground READ accentForeground NOTIFY changed)
    Q_PROPERTY(int radius READ radius NOTIFY changed)
    Q_PROPERTY(bool dark READ dark NOTIFY changed)
    Q_PROPERTY(QVariantMap colors READ colors NOTIFY changed)
    // Project colours, in a fixed order of palette slots; projects store the
    // slot index so their colour follows a theme switch.
    Q_PROPERTY(QVariantList projectColors READ projectColors NOTIFY changed)

public:
    explicit Theme(const QString &currentDirectory = {}, QObject *parent = nullptr, const QString &hyprctl = {});
    ~Theme() override;

    QString accent() const { return m_colors.value("accent").toString(); }
    QString accentForeground() const;
    int radius() const { return m_radius; }
    bool dark() const { return m_dark; }
    QVariantMap colors() const { return m_colors; }
    QVariantList projectColors() const;

    static QVariantMap readColors(const QString &path, bool *dark = nullptr);
    static QVariantMap fallbackColors();
    static QStringList projectSlots();

signals:
    void changed();

private:
    void reload();
    void refreshRounding();

    QString m_directory;
    QVariantMap m_colors = fallbackColors();
    bool m_dark = true;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QString m_hyprctl;
    int m_radius = 0;
    QProcess m_roundingProcess;
    QTimer m_roundingPoll, m_roundingTimeout;
};
