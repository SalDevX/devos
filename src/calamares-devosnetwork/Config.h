/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * DevOS Calamares view module: devosnetwork — Config (backend)
 *
 * Backend for the "connect before you install" network page. It drives
 * NetworkManager through nmcli (QProcess), exposes the Wi-Fi list and the
 * connection state to the QML UI, and is deliberately incapable of blocking
 * the installer: Skip is always available and isComplete() is forced true the
 * moment the user skips.
 *
 * This is a *view* module backend (Config object exposed to QML by the
 * QmlViewStep). It performs NO installation work — jobs() on the view step is
 * empty; the page only establishes connectivity for the modules that follow.
 */
#ifndef DEVOSNETWORK_CONFIG_H
#define DEVOSNETWORK_CONFIG_H

#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>
#include <QVariantList>

class Config : public QObject
{
    Q_OBJECT

    Q_PROPERTY( State state READ state NOTIFY stateChanged )
    Q_PROPERTY( QString statusMessage READ statusMessage NOTIFY stateChanged )
    Q_PROPERTY( bool ethernetConnected READ ethernetConnected NOTIFY connectivityChanged )
    Q_PROPERTY( bool online READ online NOTIFY connectivityChanged )
    Q_PROPERTY( bool nmcliAvailable READ nmcliAvailable NOTIFY stateChanged )
    Q_PROPERTY( bool busy READ busy NOTIFY stateChanged )
    Q_PROPERTY( QVariantList networks READ networks NOTIFY networksChanged )

    // Convenience state flags for the QML — avoids comparing the raw enum int,
    // which is brittle if the enum is ever reordered.
    Q_PROPERTY( bool complete READ isComplete NOTIFY completeChanged )
    Q_PROPERTY( bool connecting READ connecting NOTIFY stateChanged )
    Q_PROPERTY( bool connected READ connected NOTIFY stateChanged )
    Q_PROPERTY( bool failed READ failed NOTIFY stateChanged )
    Q_PROPERTY( bool skipped READ skipped NOTIFY stateChanged )
    Q_PROPERTY( bool unavailable READ unavailable NOTIFY stateChanged )

public:
    enum State
    {
        Idle,                // ready, not connected
        Scanning,            // refreshing the wifi list
        Connecting,          // nmcli connect in flight
        Connected,           // wifi connect succeeded
        Failed,              // last connect attempt failed (see statusMessage)
        Skipped,             // user pressed Skip — never blocks
        NoNetworkManager     // nmcli/NetworkManager unavailable — offer Skip
    };
    Q_ENUM( State )

    explicit Config( QObject* parent = nullptr );
    ~Config() override;

    State state() const { return m_state; }
    QString statusMessage() const { return m_statusMessage; }
    bool ethernetConnected() const { return m_ethernetConnected; }
    bool online() const { return m_ethernetConnected || m_state == Connected; }
    bool nmcliAvailable() const { return m_nmcliAvailable; }
    bool busy() const { return m_state == Scanning || m_state == Connecting; }
    QVariantList networks() const { return m_networks; }

    bool connecting() const { return m_state == Connecting; }
    bool connected() const { return m_state == Connected; }
    bool failed() const { return m_state == Failed; }
    bool skipped() const { return m_state == Skipped; }
    bool unavailable() const { return m_state == NoNetworkManager || !m_nmcliAvailable; }

    // Tunables, set from devosnetwork.conf via setConfigurationMap().
    void setRefreshIntervalMs( int ms );
    void setConnectTimeoutMs( int ms );

    /// Calamares may advance when ethernet is up, wifi connected, or skipped.
    bool isComplete() const;

public Q_SLOTS:
    void refresh();                                                  // rescan connectivity + wifi
    void connectToWifi( const QString& ssid, const QString& password );
    void skip();                                                     // ALWAYS allowed — never blocks
    void startAutoRefresh();                                         // begin 5s polling (page shown)
    void stopAutoRefresh();                                          // (page hidden)

Q_SIGNALS:
    void stateChanged();
    void connectivityChanged();
    void networksChanged();
    void completeChanged();                                          // -> QmlViewStep::nextStatusChanged
    void connectionFailed( const QString& reason );
    void connectionSucceeded();

private Q_SLOTS:
    void onConnectFinished( int exitCode, QProcess::ExitStatus status );
    void onConnectTimeout();

private:
    void setState( State s, const QString& message = QString() );
    bool ensureNetworkManager();                                    // start NM once if inactive
    void probeNmcli();
    void scanConnectivity();                                        // ethernet / online
    void scanWifi();                                                // populate m_networks

    static QStringList splitNmcliTerse( const QString& line );      // honour -t backslash escaping
    static QString securityLabel( const QString& raw );             // WPA2/WPA3/Open

    State m_state = Idle;
    QString m_statusMessage;
    bool m_ethernetConnected = false;
    bool m_nmcliAvailable = false;
    bool m_nmTriedStart = false;
    QVariantList m_networks;

    QString m_nmcli;                                                // resolved nmcli path
    int m_refreshIntervalMs = 5000;                                 // 5s default
    int m_connectTimeoutMs = 15000;                                 // 15s default

    QTimer m_refreshTimer;
    QProcess* m_connectProc = nullptr;
    QTimer m_connectTimeout;
    QString m_pendingSsid;
};

#endif  // DEVOSNETWORK_CONFIG_H
