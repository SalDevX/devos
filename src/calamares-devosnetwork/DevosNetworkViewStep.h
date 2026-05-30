/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * DevOS Calamares view module: devosnetwork — ViewStep
 *
 * Thin QmlViewStep that hosts the network page and exposes Config to the QML as
 * "config" (via getConfig()). It contributes NO install jobs — the page only
 * establishes connectivity for the modules that run afterwards. Next is enabled
 * only when Config::isComplete() (wired, Wi-Fi connected, or skipped).
 */
#ifndef DEVOSNETWORKVIEWSTEP_H
#define DEVOSNETWORKVIEWSTEP_H

#include "Config.h"

#include "DllMacro.h"
#include "utils/PluginFactory.h"
#include "viewpages/QmlViewStep.h"

#include <QObject>

class PLUGINDLLEXPORT DevosNetworkViewStep : public Calamares::QmlViewStep
{
    Q_OBJECT

public:
    explicit DevosNetworkViewStep( QObject* parent = nullptr );
    ~DevosNetworkViewStep() override;

    QString prettyName() const override;

    bool isNextEnabled() const override;
    bool isBackEnabled() const override;
    bool isAtBeginning() const override;
    bool isAtEnd() const override;

    Calamares::JobList jobs() const override;

    void setConfigurationMap( const QVariantMap& configurationMap ) override;

    QObject* getConfig() override;  // base is non-const + protected; we widen to public

    void onActivate() override;
    void onLeave() override;

private:
    Config* m_config;
};

CALAMARES_PLUGIN_FACTORY_DECLARATION( DevosNetworkViewStepFactory )

#endif  // DEVOSNETWORKVIEWSTEP_H
