FROM alpine:3.20.2

# apk upgrade in a separate layer (musl is huge)
RUN apk upgrade --no-cache --update

# Bring in tzdata and runtime libs into their own layer
RUN apk add --no-cache --update tzdata pcre zlib libssl3 luajit lua-resty-core

# If set to 1, enables building debug version of nginx, which is super-useful, but also heavy to build.
ARG DEBUG_BUILD="0"
ENV DO_DEBUG_BUILD="$DEBUG_BUILD"

# ngx_devel_kit
# https://github.com/vision5/ngx_devel_kit
# The NDK is now considered to be stable.
ARG VER_NGX_DEVEL_KIT=0.3.3
ENV VER_NGX_DEVEL_KIT=$VER_NGX_DEVEL_KIT

ENV NGINX_VERSION 1.25.5

# lua-nginx-module
# https://github.com/openresty/lua-nginx-module
# Production ready.
ARG VER_LUA_NGINX_MODULE=0.10.26
ENV VER_LUA_NGINX_MODULE=$VER_LUA_NGINX_MODULE




# nginx layer
RUN CONFIG="\
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-threads \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-http_slice_module \
    --with-compat \
    --with-file-aio \
    --with-http_v2_module \
    --add-module=/tmp/lua-nginx-module-${VER_LUA_NGINX_MODULE} \
    --add-module=/tmp/ngx_devel_kit-${VER_NGX_DEVEL_KIT} \
    " \
    && addgroup -S nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
    && apk add --no-cache --update --virtual .build-deps gcc libc-dev make openssl-dev pcre-dev zlib-dev linux-headers patch curl git luajit-dev \
    && export LUAJIT_LIB=/usr/lib \
    && export LUAJIT_INC=/usr/include/luajit-2.1 \
    && curl -fSL https://github.com/simpl/ngx_devel_kit/archive/v${VER_NGX_DEVEL_KIT}.tar.gz -o /tmp/ndk.tar.gz \
    && tar -xvf /tmp/ndk.tar.gz -C /tmp \
    && curl -fSL https://github.com/openresty/lua-nginx-module/archive/v${VER_LUA_NGINX_MODULE}.tar.gz -o /tmp/lua-nginx.tar.gz \
    && tar -xvf /tmp/lua-nginx.tar.gz -C /tmp \
    && curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
    && git clone https://github.com/chobits/ngx_http_proxy_connect_module.git /usr/src/ngx_http_proxy_connect_module \
    && cd /usr/src/ngx_http_proxy_connect_module && export PROXY_CONNECT_MODULE_PATH="$(pwd)" && cd - \
    && CONFIG="$CONFIG --add-module=$PROXY_CONNECT_MODULE_PATH" \
    && mkdir -p /usr/src \
    && tar -zxC /usr/src -f nginx.tar.gz \
    && rm nginx.tar.gz \
    && cd /usr/src/nginx-$NGINX_VERSION \
    && patch -p1 < $PROXY_CONNECT_MODULE_PATH/patch/proxy_connect_rewrite_102101.patch \
    && [ "a$DO_DEBUG_BUILD" == "a1" ] && { echo "Bulding DEBUG" &&  ./configure $CONFIG --with-debug && make -j$(getconf _NPROCESSORS_ONLN) && mv objs/nginx objs/nginx-debug ; } || { echo "Not building debug"; } \
    && { echo "Bulding RELEASE" && ./configure $CONFIG  && make -j$(getconf _NPROCESSORS_ONLN) && make install; } \
    && ls -laR objs/addon/ngx_http_proxy_connect_module/ \
    && rm -rf /etc/nginx/html/ \
    && mkdir /etc/nginx/conf.d/ \
    && mkdir -p /usr/share/nginx/html/ \
    && install -m644 html/index.html /usr/share/nginx/html/ \
    && install -m644 html/50x.html /usr/share/nginx/html/ \
    && [ "a$DO_DEBUG_BUILD" == "a1" ] && { install -m755 objs/nginx-debug /usr/sbin/nginx-debug; } || { echo "Not installing debug..."; } \
    && mkdir -p /usr/lib/nginx/modules \
    && ln -s /usr/lib/nginx/modules /etc/nginx/modules \
    && strip /usr/sbin/nginx* \
    && rm -rf /usr/src/nginx-$NGINX_VERSION \
    && rm -rf /tmp/ngx_devel_kit-${VER_NGX_DEVEL_KIT} \
    && rm -rf /tmp/lua-nginx-module-${VER_LUA_NGINX_MODULE} \
    \
    # Remove -dev apks and sources
    && apk del .build-deps gcc libc-dev make openssl-dev pcre-dev zlib-dev linux-headers patch curl git luajit-dev && rm -rf /usr/src \
    \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

#RUN ls -laR /usr/share/nginx /etc/nginx /etc/nginx/modules/ /usr/lib/nginx

# Basic sanity testing.
RUN nginx -V 2>&1 && nginx -t && ldd /usr/sbin/nginx && apk list && rm -rf /run/nginx.pid /var/cache/nginx/*_temp

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]