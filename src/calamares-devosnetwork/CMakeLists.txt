# === DevOS in-tree Calamares view module: devosnetwork ===
#
#   SPDX-License-Identifier: BSD-2-Clause
#
# This directory is injected into the upstream Calamares source tree at
# src/modules/devosnetwork by devos/pkgbuilds/calamares/PKGBUILD (prepare()),
# then auto-discovered by src/modules/CMakeLists.txt, which globs the module
# subdirectories. Mirrors the stock QML view modules (welcomeq / localeq).
#
# Runtime configuration lives in the DevOS airootfs at
# /etc/calamares/modules/devosnetwork.conf and is loaded by Calamares at module
# init (settings.conf modules-search lists /etc/calamares/modules first). So it
# can still be tuned without a Calamares rebuild.
#
# We deliberately do NOT pass NO_CONFIG: that stamps `noconfig: true` into the
# generated module.desc, which makes Calamares' getConfigFileName() return ""
# (ModuleManager.cpp) and skip the .conf entirely — leaving qmlSearch/qmlFilename
# and the refresh/timeout tunables silently ignored. Because there is no *.conf
# in THIS source dir, calamares_add_plugin prints a cosmetic
# "NO_CONFIG should be set." line at configure time — that is expected and
# harmless (the config ships from the airootfs, not from here). The module.desc
# is generated automatically from name + TYPE, and Calamares::calamaresui is
# linked automatically for TYPE viewmodule.

if(NOT WITH_QML)
    calamares_skip_module( "devosnetwork (QML is not supported in this build)" )
    return()
endif()

calamares_add_plugin( devosnetwork
    TYPE viewmodule
    EXPORT_MACRO PLUGINDLLEXPORT_PRO
    SOURCES
        DevosNetworkViewStep.cpp
        Config.cpp
    RESOURCES
        devosnetwork.qrc
    SHARED_LIB
)
