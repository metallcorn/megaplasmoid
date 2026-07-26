import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "folder-cloud"
        source: "configGeneral.qml"
    }

    // Управление синхронизациями и маунтами. Это состояние сервера MEGAcmd, а не
    // настройки виджета, поэтому страница применяет изменения сразу и не имеет
    // свойств cfg_*.
    ConfigCategory {
        name: i18n("Folders")
        icon: "folder-sync"
        source: "configFolders.qml"
    }
}
