SUMMARY = "Recipe to embedded the Python PiP Package krpc"
HOMEPAGE ="https://pypi.org/project/krpc"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=37b5762e07f0af8c74ce80a8bda4266b"

inherit setuptools3
SRC_URI = "https://files.pythonhosted.org/packages/da/01/9ef0afd7999eb9badb3a768b4aedd78c86d4c65cfaf1958ab276199e76b4/protobuf-7.35.1.tar.gz"
SRC_URI[md5sum] = "e9074f4f40672c900f878be049f86cb8"
SRC_URI[sha256sum] = "ce115a26fe0c39a2c29973d914d327e516a6455464489fe3cd1e51a1b354f81a"
S = "${WORKDIR}/protobuf-7.35.1"
