SUMMARY = "Recipe to embedded the Python PiP Package krpc"
HOMEPAGE ="https://pypi.org/project/krpc"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://COPYING;md5=1ebbd3e34237af26da5dc08a4e440464"

DEPENDS += "py-protobuf"

inherit setuptools3
SRC_URI = "https://files.pythonhosted.org/packages/1d/d9/fe6f07c1fa993e23ec5d8d9d02165c7ae72b5362ae5713dd9768753c41f2/krpc-0.5.4.zip"
SRC_URI[md5sum] = "432b6f7841b5fa3bdea678d854d13ac9"
SRC_URI[sha256sum] = "95b4512a080c92d45a1b60ebb9eff9290c5263a19ff1abdb351e12ffb51fb615"
S = "${WORKDIR}/krpc-0.5.4"