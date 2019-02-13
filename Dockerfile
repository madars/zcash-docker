FROM alpine:edge as builder
LABEL maintainer "Madars Virza <madars@mit.edu>"

ENV ZCASH_VERSION=master
# You can specify a particular version above, e.g. ZCASH_VERSION=v2.0.3

RUN apk --no-cache add --virtual .build-deps \
        build-base \
        bash \
        git \
        curl \
        tar \
        perl \
        automake \
        autoconf \
        libtool \
        patch \
        rust \
        cargo \
        pkgconf

RUN adduser -D build

USER build
WORKDIR /home/build
RUN git clone https://github.com/zcash/zcash.git

ENV ZCASH_BUILDDIR /home/build/zcash
WORKDIR ${ZCASH_BUILDDIR}
RUN git checkout ${ZCASH_VERSION}

# patch gmp (see README.md)
COPY patches/gmp.patch ${ZCASH_BUILDDIR}/gmp.patch
RUN git apply gmp.patch

# build Zcash
RUN ./zcutil/build.sh

###############################################################################

FROM alpine:edge as node
LABEL maintainer "Madars Virza <madars@mit.edu>"

# install dependencies for zcashd and zcash-fetch-params
RUN apk --no-cache add libgomp libstdc++ libgcc wget ca-certificates

# install man page utilties and bash completion
RUN apk --no-cache add bash bash-completion man mdocml-apropos

# copy over files from the builder container above

# the lists here are based on what
# https://github.com/zcash/zcash/blob/master/zcutil/build-debian-package.sh
# does, except that we also include zcash-tx and zcash-gtest
ENV ZCASH_BUILDDIR /home/build/zcash
COPY --from=builder ${ZCASH_BUILDDIR}/src/zcash-cli /usr/bin/zcash-cli
COPY --from=builder ${ZCASH_BUILDDIR}/src/zcash-gtest /usr/bin/zcash-gtest
COPY --from=builder ${ZCASH_BUILDDIR}/src/zcash-tx /usr/bin/zcash-tx
COPY --from=builder ${ZCASH_BUILDDIR}/src/zcashd /usr/bin/zcashd
COPY --from=builder ${ZCASH_BUILDDIR}/zcutil/fetch-params.sh /usr/bin/zcash-fetch-params

COPY --from=builder ${ZCASH_BUILDDIR}/doc/man/zcash-cli.1 /usr/share/man/man1/zcashd-cli.1
COPY --from=builder ${ZCASH_BUILDDIR}/doc/man/zcash-fetch-params.1 /usr/share/man/man1/zcash-fetch-params.1
COPY --from=builder ${ZCASH_BUILDDIR}/doc/man/zcash-tx.1 /usr/share/man/man1/zcash-tx.1
COPY --from=builder ${ZCASH_BUILDDIR}/doc/man/zcashd.1 /usr/share/man/man1/zcashd.1

COPY --from=builder ${ZCASH_BUILDDIR}/contrib/zcash-cli.bash-completion /usr/share/bash-completion/completions/zcash-cli
COPY --from=builder ${ZCASH_BUILDDIR}/contrib/zcash-tx.bash-completion /usr/share/bash-completion/completions/zcash-tx
COPY --from=builder ${ZCASH_BUILDDIR}/contrib/zcashd.bash-completion /usr/share/bash-completion/completions/zcashd

COPY --from=builder ${ZCASH_BUILDDIR}/contrib/debian/changelog /usr/share/doc/zcash/changelog
COPY --from=builder ${ZCASH_BUILDDIR}/contrib/debian/copyright /usr/share/doc/zcash/copyright

COPY --from=builder ${ZCASH_BUILDDIR}/contrib/debian/examples/zcash.conf /usr/share/doc/zcash/examples/zcash.conf

# reindex man pages
RUN makewhatis /usr/share/man

# create a default user and two directories that we'll use as volume
# targets in "docker run" invocation
RUN adduser -D user
USER user
ENV HOME /home/user
WORKDIR /home/user
RUN mkdir $HOME/.zcash-params $HOME/.zcash
