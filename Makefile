# Сборка и установка плазмоида. Внешних зависимостей нет: каталог переводов
# компилирует свой скрипт на Python, пакет — обычный zip.

PLUGIN_ID  := org.kde.plasma.megacmd
DOMAIN     := plasma_applet_$(PLUGIN_ID)
PACKAGE    := megaplasmoid.plasmoid

PLASMOID_DIR := $(HOME)/.local/share/plasma/plasmoids/$(PLUGIN_ID)
NOTIFY_DIR   := $(HOME)/.local/share/knotifications6
LOCALE_DIR   := $(HOME)/.local/share/locale

PO_FILES := $(wildcard po/*.po)

.PHONY: all mo package install uninstall reload clean

all: package

## Компилирует po/*.po в contents/locale/<язык>/LC_MESSAGES/
mo: $(PO_FILES)
	python3 po/build-mo.py

## Собирает .plasmoid (это просто zip с metadata.json и contents/)
package: mo
	rm -f $(PACKAGE)
	zip -qr $(PACKAGE) metadata.json contents
	@echo "готово: $(PACKAGE)"

## Ставит в домашний каталог. Копированием, а не kpackagetool6 --upgrade:
## на каталог, который сам является местом установки, тот удаляет пакет
## перед переустановкой из него же и оставляет пустоту.
install: mo
	rm -rf $(PLASMOID_DIR)
	mkdir -p $(PLASMOID_DIR)
	cp -r metadata.json contents $(PLASMOID_DIR)/
	@echo "установлено: $(PLASMOID_DIR)"
	@echo "перезапустите оболочку: kquitapp6 plasmashell && kstart plasmashell"

uninstall:
	rm -rf $(PLASMOID_DIR)
	rm -f $(NOTIFY_DIR)/plasma_applet_megacmd.notifyrc
	rm -f $(LOCALE_DIR)/*/LC_MESSAGES/$(DOMAIN).mo
	@echo "удалено"

reload:
	kquitapp6 plasmashell && kstart plasmashell

clean:
	rm -f $(PACKAGE)
	rm -rf contents/locale
