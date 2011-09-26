#include <QCoreApplication>
#include <QString>
#include <QList>
#include <stdio.h>
#include "RBuild.h"
#include "Utils.h"
#include "PreCompile.h"
#include "ClangRunnable.h"
#include <syslog.h>
#include <getopt.h>
#include "Shared.h"

void syslogMsgHandler(QtMsgType t, const char* str)
{
    int priority = LOG_WARNING;
    static const char *names[] = { "DEBUG", "WARNING", "CRITICAL", "FATAL" };
    const bool noColors = getenv("RTAGS_CONSOLE_NO_COLOR");
    const char *colorStart = "";
    const char *colorEnd = "";

    switch (t) {
    case QtDebugMsg:
        colorStart = "\x1b[36m"; // cyan
        priority = LOG_DEBUG;
        break;
    case QtWarningMsg:
        colorStart = "\x1b[31m"; // red
        priority = LOG_WARNING;
        break;
    case QtCriticalMsg:
        colorStart = "\x1b[31m";
        priority = LOG_CRIT;
        break;
    case QtFatalMsg:
        colorStart = "\x1b[41;37m";
        priority = LOG_CRIT;
        break;
    }
    if (noColors) {
        colorStart = "";
    } else if (colorStart) {
        colorEnd = "\x1b[0m";
    }
    fprintf(stderr, "%s%s: %s%s\n", colorStart,
            qPrintable(QDateTime::currentDateTime().toString()),
            str, colorEnd);
    char buf[16384];
    const int s = snprintf(buf, 16383, "%s (%s): %s (%s)\n",
                           qPrintable(QDateTime::currentDateTime().toString()),
                           qPrintable(QThread::currentThread()->objectName()),
                           str,
                           names[t]);

    static QMutex sFileLock;
    {
        QMutexLocker lock(&sFileLock);
        QFile file("/tmp/rtags.log");
        file.open(QIODevice::WriteOnly|QIODevice::Append);
        file.write(buf, s);
    }
    syslog(priority, "%s (%s)\n", str, names[t]);
}

int main(int argc, char** argv)
{
    if (QFile::exists("/tmp/rtags.log")) {
        int idx = 1;
        while (QFile::exists(QString("/tmp/rtags.log.%1").arg(idx)))
            ++idx;
        QFile::rename("/tmp/rtags.log", QString("/tmp/rtags.log.%1").arg(idx));
    }
    qInstallMsgHandler(syslogMsgHandler);

    struct option longOptions[] = {
        { "help", 0, 0, 'h' },
        { "update-db", optional_argument, 0, 'u' },
        { "srcdir", required_argument, 0, 's' },
        { 0, 0, 0, 0 },
    };
    const char *shortOptions = "hu::s:";
    int idx, longIndex;
    
    QCoreApplication app(argc, argv);
    QThread::currentThread()->setObjectName("main");
    QCoreApplication::setOrganizationDomain("www.rtags.com");
    QCoreApplication::setOrganizationName("rtags");
    QCoreApplication::setApplicationName("rtags");

    PreCompile::setPath("/tmp");

    RBuild rbuild;
    bool update = false;
    const char *dbFile = 0;
    while ((idx = getopt_long(argc, argv, shortOptions, longOptions, &longIndex)) != -1) {
        switch (idx) {
        case 'h':
        case 's':
            break;
        case 'u':
            update = true;
            if (optarg) {
                dbFile = *optarg == '=' ? optarg + 1 : optarg;
            } else if (optind < argc && *argv[optind] != '-') { // ### optind is off by one for some reason
                dbFile = argv[optind];
                argv[optind] = 0;
            }
            break;
        default:
            break;
        }
    }

    class ClangRunnableScope
    {
    public:
        ClangRunnableScope() { ClangRunnable::init(); }
        ~ClangRunnableScope() { ClangRunnable::cleanup(); }
    } scope;

    for (int i=1; i<argc; ++i) {
        if (argv[i] && *argv[i] != '-') {
            if (update) {
                printf("%s %d: if (update) {\n", __FILE__, __LINE__);
                return 1;
            } else {
                if (!rbuild.addMakefile(argv[i])) {
                    printf("%s %d: if (!rbuild.addMakefile(argv[i]))\n", __FILE__, __LINE__);
                    return 1;
                }
            }
        }
    }

    if (dbFile) {
        rbuild.setDatabaseFile(dbFile, update ? RBuild::Update : RBuild::Build);
    } else if (!rbuild.findDatabaseFile(update ? RBuild::Update : RBuild::Build)) {
        printf("%s %d: } else if (!rbuild.detectDatabaseFile(update ? RBuild::Update : RBuild::Build)) {\n", __FILE__, __LINE__);
        return 1;
    }


    return app.exec();
}
