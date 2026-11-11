ARG KONG_IMAGE=kong:3.9.4
FROM ${KONG_IMAGE}
USER root
COPY kong/plugins/guance-log /usr/local/share/lua/5.1/kong/plugins/guance-log
ENV KONG_PLUGINS=bundled,guance-log
USER kong
