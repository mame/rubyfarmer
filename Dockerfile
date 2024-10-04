FROM mametter/ruby-build-env:latest AS build
LABEL stage=rubyfarmer-builder
COPY ruby.git ruby.git
ARG COMMIT=${COMMIT:-master}
RUN git clone ruby.git && \
  cd ruby && \
  git checkout ${COMMIT} && \
  ./autogen.sh && \
  ./configure --prefix=/opt/ruby --enable-shared && \
  make extract-gems && \
  make && \
  make install

FROM mametter/ruby-build-env:latest
ENV PATH /opt/ruby/bin:$PATH
ENV LD_LIBRARY_PATH /usr/local/lib:$LD_LIBRARY_PATH
LABEL maintainer "Yusuke Endoh <mame@ruby-lang.org>"
COPY --from=build /opt/ruby /opt/ruby
