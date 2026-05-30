/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * DevOS Calamares view module: devosnetwork — ViewStep implementation
 */
#include "DevosNetworkViewStep.h"

#include "Config.h"

#include "utils/Logger.h"
#include "utils/Variant.h"

#include <QVariantMap>

CALAMARES_PLUGIN_FACTORY_DEFINITION( DevosNetworkViewStepFactory, registerPlugin< DevosNetworkViewStep >(); )

DevosNetworkViewStep::DevosNetworkViewStep( QObject* parent )
    : Calamares::QmlViewStep( parent )
    , m_config( new Config( this ) )
{
    // Re-evaluate Next whenever connectivity / skip state changes. A lambda keeps
    // us decoupled from nextStatusChanged(bool)'s exact arity.
    connect( m_config, &Config::completeChanged, this, [ this ] { emit nextStatusChanged( isNextEnabled() ); } );
}

DevosNetworkViewStep::~DevosNetworkViewStep() {}

QString
DevosNetworkViewStep::prettyName() const
{
    return tr( "Network" );
}

bool
DevosNetworkViewStep::isNextEnabled() const
{
    return m_config->isComplete();
}

bool
DevosNetworkViewStep::isBackEnabled() const
{
    return false;  // first page in the sequence — nothing to go back to
}

bool
DevosNetworkViewStep::isAtBeginning() const
{
    return true;
}

bool
DevosNetworkViewStep::isAtEnd() const
{
    return true;
}

Calamares::JobList
DevosNetworkViewStep::jobs() const
{
    return Calamares::JobList();  // connectivity only — contributes no install jobs
}

void
DevosNetworkViewStep::setConfigurationMap( const QVariantMap& configurationMap )
{
    m_config->setRefreshIntervalMs(
        static_cast< int >( Calamares::getInteger( configurationMap, "refreshIntervalMs", 5000 ) ) );
    m_config->setConnectTimeoutMs(
        static_cast< int >( Calamares::getInteger( configurationMap, "connectTimeoutMs", 15000 ) ) );

    // Base reads qmlSearch / qmlFilename and resolves the QML to load.
    Calamares::QmlViewStep::setConfigurationMap( configurationMap );
}

QObject*
DevosNetworkViewStep::getConfig()
{
    return m_config;
}

void
DevosNetworkViewStep::onActivate()
{
    Calamares::QmlViewStep::onActivate();  // builds the QML, exposes `config`
    m_config->startAutoRefresh();
}

void
DevosNetworkViewStep::onLeave()
{
    m_config->stopAutoRefresh();
    Calamares::QmlViewStep::onLeave();
}
