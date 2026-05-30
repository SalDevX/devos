/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * DevOS Calamares view module: devosnetwork — Config (backend)
 *
 * Drives NetworkManager through nmcli (QProcess, never a shell — argv goes
 * straight to execve, so SSIDs/passwords cannot be shell-injected). Exposes the
 * Wi-Fi list and connection state to the QML page. By design it cannot block the
 * installer: skip() always succeeds and forces isComplete() true.
 */
#include "Config.h"

#include "utils/Logger.h"

#include <QProcess>
#include <QSet>
#include <QStandardPaths>
#include <QStringList>

namespace
{
/** Run @p prog with @p args synchronously (no shell). Returns stdout; sets
 *  @p exitCode (-1 on start/timeout failure) and @p stderrOut when given.
 *  Used only for quick reads (status, wifi list) — the connect itself is async.
 */
QString
runProcess( const QString& prog, const QStringList& args, int timeoutMs, int* exitCode = nullptr, QString* stderrOut = nullptr )
{
    QProcess p;
    p.start( prog, args );
    if ( !p.waitForStarted( 3000 ) )
    {
        if ( exitCode )
        {
            *exitCode = -1;
        }
        return QString();
    }
    if ( !p.waitForFinished( timeoutMs ) )
    {
        p.kill();
        p.waitForFinished( 1000 );
        if ( exitCode )
        {
            *exitCode = -1;
        }
        return QString();
    }
    if ( exitCode )
    {
        *exitCode = p.exitCode();
    }
    if ( stderrOut )
    {
        *stderrOut = QString::fromUtf8( p.readAllStandardError() );
    }
    return QString::fromUtf8( p.readAllStandardOutput() );
}
}  // namespace

Config::Config( QObject* parent )
    : QObject( parent )
{
    m_refreshTimer.setInterval( m_refreshIntervalMs );
    connect( &m_refreshTimer, &QTimer::timeout, this, &Config::refresh );

    m_connectTimeout.setSingleShot( true );
    connect( &m_connectTimeout, &QTimer::timeout, this, &Config::onConnectTimeout );

    probeNmcli();
}

Config::~Config()
{
    m_refreshTimer.stop();
    m_connectTimeout.stop();
    if ( m_connectProc )
    {
        disconnect( m_connectProc, nullptr, this, nullptr );
        m_connectProc->kill();
        m_connectProc->waitForFinished( 500 );
    }
}

void
Config::setRefreshIntervalMs( int ms )
{
    if ( ms >= 1000 )
    {
        m_refreshIntervalMs = ms;
        if ( m_refreshTimer.isActive() )
        {
            m_refreshTimer.start( m_refreshIntervalMs );
        }
    }
}

void
Config::setConnectTimeoutMs( int ms )
{
    if ( ms >= 3000 )
    {
        m_connectTimeoutMs = ms;
    }
}

bool
Config::isComplete() const
{
    // Wired up, Wi-Fi connected, or the user chose Skip — any of these unblocks
    // Next. Skip is the guarantee that offline / wired installs never stall here.
    return m_state == Skipped || m_state == Connected || m_ethernetConnected;
}

void
Config::setState( State s, const QString& message )
{
    m_state = s;
    if ( !message.isNull() )
    {
        m_statusMessage = message;
    }
    emit stateChanged();
}

void
Config::probeNmcli()
{
    m_nmcli = QStandardPaths::findExecutable( QStringLiteral( "nmcli" ) );
    m_nmcliAvailable = !m_nmcli.isEmpty();
    if ( !m_nmcliAvailable )
    {
        cWarning() << "[devosnetwork] nmcli not found — offering Skip only.";
        setState( NoNetworkManager, tr( "Network management tool (nmcli) is not available." ) );
    }
}

bool
Config::ensureNetworkManager()
{
    if ( !m_nmcliAvailable )
    {
        return false;
    }

    const QString systemctl = QStandardPaths::findExecutable( QStringLiteral( "systemctl" ) );
    auto nmActive = [&]() -> bool {
        if ( systemctl.isEmpty() )
        {
            // No systemctl: fall back to asking nmcli whether it is running.
            int ec = 0;
            const QString out = runProcess( m_nmcli, { "-t", "-f", "RUNNING", "general" }, 3000, &ec ).trimmed();
            return ec == 0 && out == QLatin1String( "running" );
        }
        int ec = 0;
        const QString out = runProcess( systemctl, { "is-active", "NetworkManager" }, 3000, &ec ).trimmed();
        return out == QLatin1String( "active" );
    };

    if ( nmActive() )
    {
        return true;
    }

    // Not running — try to start it exactly once (Calamares runs as root).
    if ( m_nmTriedStart )
    {
        setState( NoNetworkManager, tr( "NetworkManager is not running." ) );
        return false;
    }
    m_nmTriedStart = true;
    cWarning() << "[devosnetwork] NetworkManager inactive — attempting to start it once.";
    if ( !systemctl.isEmpty() )
    {
        int ec = 0;
        runProcess( systemctl, { "start", "NetworkManager" }, 8000, &ec );
        if ( nmActive() )
        {
            return true;
        }
    }
    setState( NoNetworkManager, tr( "NetworkManager could not be started." ) );
    return false;
}

void
Config::scanConnectivity()
{
    if ( !m_nmcliAvailable )
    {
        return;
    }
    int ec = 0;
    const QString out = runProcess( m_nmcli, { "-t", "-f", "DEVICE,TYPE,STATE", "device", "status" }, 4000, &ec );
    if ( ec != 0 )
    {
        return;
    }
    bool eth = false;
    const auto lines = out.split( QLatin1Char( '\n' ), Qt::SkipEmptyParts );
    for ( const QString& line : lines )
    {
        const QStringList f = splitNmcliTerse( line );
        if ( f.size() >= 3 && f.at( 1 ) == QLatin1String( "ethernet" )
             && f.at( 2 ).startsWith( QLatin1String( "connected" ) ) )
        {
            eth = true;
            break;
        }
    }
    if ( eth != m_ethernetConnected )
    {
        m_ethernetConnected = eth;
        emit connectivityChanged();
        emit completeChanged();
        if ( eth && m_state == Idle )
        {
            setState( Idle, tr( "Wired connection active — you're online." ) );
        }
    }
}

void
Config::scanWifi()
{
    if ( !m_nmcliAvailable )
    {
        return;
    }
    int ec = 0;
    const QString out = runProcess( m_nmcli, { "-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list" }, 6000, &ec );
    if ( ec != 0 )
    {
        return;  // NM may still be settling — keep the previous list.
    }

    QVariantList nets;
    QSet< QString > seen;
    const auto lines = out.split( QLatin1Char( '\n' ), Qt::SkipEmptyParts );
    for ( const QString& line : lines )
    {
        const QStringList f = splitNmcliTerse( line );
        if ( f.size() < 3 )
        {
            continue;
        }
        const QString ssid = f.at( 0 );
        if ( ssid.isEmpty() )
        {
            continue;  // hidden network — nothing to click
        }
        if ( seen.contains( ssid ) )
        {
            continue;  // list is signal-sorted; keep the strongest BSS per SSID
        }
        seen.insert( ssid );

        const QString rawSec = f.at( 2 );
        QVariantMap m;
        m.insert( QStringLiteral( "ssid" ), ssid );
        m.insert( QStringLiteral( "signal" ), f.at( 1 ).toInt() );
        m.insert( QStringLiteral( "secured" ), !rawSec.isEmpty() );
        m.insert( QStringLiteral( "security" ), securityLabel( rawSec ) );
        nets.append( m );
    }
    m_networks = nets;
    emit networksChanged();
}

void
Config::refresh()
{
    if ( !m_nmcliAvailable )
    {
        probeNmcli();  // a USB Wi-Fi dongle / nmcli may have appeared
        if ( !m_nmcliAvailable )
        {
            return;
        }
    }
    if ( !ensureNetworkManager() )
    {
        return;
    }
    if ( m_state == Connecting )
    {
        return;  // don't disturb an in-flight connect
    }
    scanConnectivity();
    scanWifi();
}

void
Config::startAutoRefresh()
{
    if ( m_nmcliAvailable && m_networks.isEmpty() && m_state == Idle )
    {
        setState( Scanning, tr( "Scanning for networks…" ) );
    }
    refresh();
    if ( m_state == Scanning )
    {
        setState( Idle, QString() );
    }
    m_refreshTimer.start( m_refreshIntervalMs );
}

void
Config::stopAutoRefresh()
{
    m_refreshTimer.stop();
}

void
Config::connectToWifi( const QString& ssid, const QString& password )
{
    if ( !m_nmcliAvailable )
    {
        setState( NoNetworkManager, tr( "nmcli is not available." ) );
        return;
    }
    if ( m_state == Connecting )
    {
        return;
    }
    if ( ssid.isEmpty() )
    {
        setState( Failed, tr( "No network selected." ) );
        emit connectionFailed( m_statusMessage );
        return;
    }

    m_pendingSsid = ssid;
    setState( Connecting, tr( "Connecting to \"%1\"…" ).arg( ssid ) );

    // argv passed directly to nmcli — no shell, so the password is never parsed
    // by a shell and cannot inject. (It is still visible in this process's argv
    // to root for the moment of the call; that is inherent to nmcli's CLI.)
    QStringList args;
    args << QStringLiteral( "device" ) << QStringLiteral( "wifi" ) << QStringLiteral( "connect" ) << ssid;
    if ( !password.isEmpty() )
    {
        args << QStringLiteral( "password" ) << password;
    }

    if ( m_connectProc )
    {
        disconnect( m_connectProc, nullptr, this, nullptr );
        m_connectProc->deleteLater();
        m_connectProc = nullptr;
    }
    m_connectProc = new QProcess( this );
    connect( m_connectProc, QOverload< int, QProcess::ExitStatus >::of( &QProcess::finished ),
             this, &Config::onConnectFinished );
    m_connectProc->start( m_nmcli, args );
    m_connectTimeout.start( m_connectTimeoutMs );
}

void
Config::onConnectFinished( int exitCode, QProcess::ExitStatus status )
{
    m_connectTimeout.stop();

    QString err;
    if ( m_connectProc )
    {
        err = QString::fromUtf8( m_connectProc->readAllStandardError() )
            + QString::fromUtf8( m_connectProc->readAllStandardOutput() );
    }

    if ( status == QProcess::NormalExit && exitCode == 0 )
    {
        setState( Connected, tr( "Connected to \"%1\"." ).arg( m_pendingSsid ) );
        emit connectivityChanged();
        emit connectionSucceeded();
        emit completeChanged();
    }
    else
    {
        const QString low = err.toLower();
        QString msg;
        if ( low.contains( QLatin1String( "secrets were required" ) ) || low.contains( QLatin1String( "no secrets" ) )
             || low.contains( QLatin1String( "802-11-wireless-security" ) ) || low.contains( QLatin1String( "password" ) ) )
        {
            msg = tr( "Incorrect password — try again." );
        }
        else if ( err.trimmed().isEmpty() )
        {
            msg = tr( "Could not connect to \"%1\"." ).arg( m_pendingSsid );
        }
        else
        {
            msg = tr( "Connection failed: %1" ).arg( err.trimmed().section( QLatin1Char( '\n' ), 0, 0 ) );
        }
        cWarning() << "[devosnetwork] Wi-Fi connect failed for" << m_pendingSsid << "exit" << exitCode;
        setState( Failed, msg );
        emit connectionFailed( msg );
    }

    if ( m_connectProc )
    {
        m_connectProc->deleteLater();
        m_connectProc = nullptr;
    }
}

void
Config::onConnectTimeout()
{
    if ( m_connectProc )
    {
        // Drop the finished() handler first so the kill doesn't also report a
        // generic failure on top of the timeout message.
        disconnect( m_connectProc, nullptr, this, nullptr );
        m_connectProc->kill();
        m_connectProc->waitForFinished( 1000 );
        m_connectProc->deleteLater();
        m_connectProc = nullptr;
    }
    cWarning() << "[devosnetwork] Wi-Fi connect timed out for" << m_pendingSsid;
    setState( Failed, tr( "Connection timed out. Try again or skip." ) );
    emit connectionFailed( m_statusMessage );
}

void
Config::skip()
{
    // Non-negotiable: skipping must always succeed and must never block Next.
    cWarning() << "[devosnetwork] User skipped the network step — continuing without verified connectivity.";
    m_connectTimeout.stop();
    if ( m_connectProc )
    {
        disconnect( m_connectProc, nullptr, this, nullptr );
        m_connectProc->kill();
        m_connectProc->deleteLater();
        m_connectProc = nullptr;
    }
    setState( Skipped, tr( "Network step skipped." ) );
    emit completeChanged();
}

QStringList
Config::splitNmcliTerse( const QString& line )
{
    // nmcli -t escapes a literal ':' as '\:' and a literal '\' as '\\'. Split on
    // unescaped ':' so SSIDs containing ':' survive intact.
    QStringList out;
    QString cur;
    for ( int i = 0; i < line.size(); ++i )
    {
        const QChar c = line.at( i );
        if ( c == QLatin1Char( '\\' ) && i + 1 < line.size() )
        {
            cur.append( line.at( ++i ) );
        }
        else if ( c == QLatin1Char( ':' ) )
        {
            out.append( cur );
            cur.clear();
        }
        else
        {
            cur.append( c );
        }
    }
    out.append( cur );
    return out;
}

QString
Config::securityLabel( const QString& raw )
{
    if ( raw.isEmpty() )
    {
        return QStringLiteral( "Open" );
    }
    if ( raw.contains( QLatin1String( "WPA3" ) ) || raw.contains( QLatin1String( "SAE" ) ) )
    {
        return QStringLiteral( "WPA3" );
    }
    if ( raw.contains( QLatin1String( "WPA2" ) ) )
    {
        return QStringLiteral( "WPA2" );
    }
    if ( raw.contains( QLatin1String( "WPA" ) ) )
    {
        return QStringLiteral( "WPA" );
    }
    if ( raw.contains( QLatin1String( "WEP" ) ) )
    {
        return QStringLiteral( "WEP" );
    }
    return QStringLiteral( "Secured" );
}
