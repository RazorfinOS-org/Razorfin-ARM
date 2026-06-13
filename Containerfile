ARG BASE_IMAGE="quay.io/fedora-ostree-desktops/cosmic-atomic:44"
ARG BOARD_TARGET="generic"
ARG DX_VARIANT="false"

FROM scratch AS ctx
COPY build_files /build
COPY fex-appconfig/AppConfig /build/fex-appconfig

FROM ${BASE_IMAGE}

ARG BOARD_TARGET
ARG DX_VARIANT

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    BOARD_TARGET=${BOARD_TARGET} DX_VARIANT=${DX_VARIANT} bash /ctx/build/00-base.sh && \
    BOARD_TARGET=${BOARD_TARGET} DX_VARIANT=${DX_VARIANT} bash /ctx/build/01-gaming.sh && \
    BOARD_TARGET=${BOARD_TARGET} DX_VARIANT=${DX_VARIANT} bash /ctx/build/02-sbc-support.sh && \
    BOARD_TARGET=${BOARD_TARGET} DX_VARIANT=${DX_VARIANT} bash /ctx/build/03-trim.sh && \
    BOARD_TARGET=${BOARD_TARGET} DX_VARIANT=${DX_VARIANT} bash /ctx/build/04-dx.sh && \
    BOARD_TARGET=${BOARD_TARGET} DX_VARIANT=${DX_VARIANT} bash /ctx/build/99-cleanup.sh

RUN bootc container lint
