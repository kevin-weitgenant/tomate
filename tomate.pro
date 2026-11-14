QT += core gui qml quick quickcontrols2 sql

CONFIG += c++17 release
TARGET = tomate
TEMPLATE = app

HEADERS += \
    src/db.h \
    src/engine.h \
    src/backend.h \
    src/cli.h \
    src/theme.h \
    src/translator.h

SOURCES += \
    src/main.cpp \
    src/db.cpp \
    src/engine.cpp \
    src/backend.cpp \
    src/cli.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
