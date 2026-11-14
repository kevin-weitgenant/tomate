QT += core gui sql testlib
CONFIG += c++17 testcase
TARGET = tomate_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/db.h ../src/engine.h ../src/theme.h ../src/translator.h
SOURCES += tomate_tests.cpp ../src/db.cpp ../src/engine.cpp ../src/theme.cpp ../src/translator.cpp
