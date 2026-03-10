# pfSense-pkg-speedtest — FreeBSD ports Makefile (BSD make)
#
# For use inside the FreeBSD ports tree:
#   cp -r pfSense-pkg-speedtest /usr/ports/sysutils/pfSense-pkg-speedtest
#   cd /usr/ports/sysutils/pfSense-pkg-speedtest && make package
#
# For macOS development builds (recommended), use the root Makefile instead:
#   make build   (requires: brew install lima)
# ---------------------------------------------------------------------------

PORTNAME=	pfSense-pkg-speedtest
DISTVERSION=	1.0.0
PORTREVISION=	0

CATEGORIES=	sysutils

MAINTAINER=	johnathan.vidu@gmail.com
COMMENT=	pfSense package to run and schedule Ookla Speedtest CLI

LICENSE=	APACHE20

# Runtime: Ookla Speedtest CLI must be installed on the pfSense box
RUN_DEPENDS=	speedtest:net/ookla-speedtest

NO_BUILD=	yes
NO_ARCH=	yes
NO_MTREE=	yes

# pkg-install handles the priv file copy to /etc/inc/priv/ at install time
SUB_FILES=	pkg-install
SUB_LIST+=	PREFIX=${PREFIX}

# The priv file is staged under share/ (within PREFIX) to satisfy pkg constraints.
# pkg-install copies it to /etc/inc/priv/ when the package is added.
PLIST_FILES=	\
		bin/speedtest_runner.sh \
		pkg/speedtest.inc \
		pkg/speedtest.xml \
		www/speedtest/speedtest.php \
		www/widgets/widgets/speedtest.widget.php \
		share/${PORTNAME}/speedtest.priv.inc

do-install:
	${MKDIR} ${STAGEDIR}${PREFIX}/bin
	${MKDIR} ${STAGEDIR}${PREFIX}/pkg
	${MKDIR} ${STAGEDIR}${PREFIX}/www/speedtest
	${MKDIR} ${STAGEDIR}${PREFIX}/www/widgets/widgets
	${MKDIR} ${STAGEDIR}${PREFIX}/share/${PORTNAME}

	${INSTALL_SCRIPT} ${FILESDIR}/usr/local/bin/speedtest_runner.sh \
		${STAGEDIR}${PREFIX}/bin/
	${INSTALL_DATA} ${FILESDIR}/usr/local/pkg/speedtest.xml \
		${STAGEDIR}${PREFIX}/pkg/
	${INSTALL_DATA} ${FILESDIR}/usr/local/pkg/speedtest.inc \
		${STAGEDIR}${PREFIX}/pkg/
	${INSTALL_DATA} ${FILESDIR}/usr/local/www/speedtest/speedtest.php \
		${STAGEDIR}${PREFIX}/www/speedtest/
	${INSTALL_DATA} ${FILESDIR}/usr/local/www/widgets/widgets/speedtest.widget.php \
		${STAGEDIR}${PREFIX}/www/widgets/widgets/
	${INSTALL_DATA} ${FILESDIR}/etc/inc/priv/speedtest.priv.inc \
		${STAGEDIR}${PREFIX}/share/${PORTNAME}/

.include <bsd.port.mk>
