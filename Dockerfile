      # GENERATED FILE, DO NOT MODIFY!
      # To update this file please edit the relevant template and run the generation
      # task `build/dockerfile_writer.rb`

# See doc/docker/README.md or https://github.com/instructure/canvas-lms/tree/master/doc/docker
FROM instructure/ruby-passenger:2.4

ENV APP_HOME /usr/src/app/
ENV RAILS_ENV "production"
ENV NGINX_MAX_UPLOAD_SIZE 10g

# Work around github.com/zertosh/v8-compile-cache/issues/2
# This can be removed once yarn pushes a release including the fixed version
# of v8-compile-cache.
ENV DISABLE_V8_COMPILE_CACHE 1

USER root
WORKDIR /root
WORKDIR $APP_HOME

COPY . $APP_HOME
COPY config/database_config config/database.yml
COPY config/security_config config/security.yml
COPY config/delayed_jobs_config config/delayed_jobs.yml
COPY config/redis_config config/redis.yml
COPY config/cache_store_config config/cache_store.yml
WORKDIR /root
RUN curl -sL https://deb.nodesource.com/setup_6.x | bash - \
  && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add - \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list \
  && printf 'path-exclude /usr/share/doc/*\npath-exclude /usr/share/man/*' > /etc/dpkg/dpkg.cfg.d/01_nodoc \
  && apt-get update -qq \
  && apt-get install -qqy --no-install-recommends \
       nodejs \
       yarn \
       libxmlsec1-dev \
       python-lxml \
       libicu-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /home/docker/.gem/ruby/$RUBY_MAJOR.0

RUN if [ -e /var/lib/gems/$RUBY_MAJOR.0/gems/bundler-* ]; then BUNDLER_INSTALL="-i /var/lib/gems/$RUBY_MAJOR.0"; fi \
  && gem uninstall --all --ignore-dependencies --force $BUNDLER_INSTALL bundler \
  && gem install bundler --no-document -v 1.14.3 \
  && gem update --system --no-document \
  && find $GEM_HOME ! -user docker | xargs chown docker:docker


WORKDIR $APP_HOME

# optimizing for size here ... get all the dev dependencies so we can
# compile assets, then throw away everything we don't need
#
# the privilege dropping could be slightly less verbose if we ever add
# gosu (here or upstream)
#
# TODO: once we have docker 17.05+ everywhere, do this via multi-stage
# build

RUN bash -c ' \
  # bash cuz better globbing and comments \
  set -e; \
  \
  sudo -u docker -E env HOME=/home/docker PATH=$PATH bundle install --jobs 8; \
  yarn install --pure-lockfile; \
  COMPILE_ASSETS_NPM_INSTALL=0 bundle exec rake canvas:compile_assets; \
  \
  # downgrade to prod dependencies \
  sudo -u docker -E env HOME=/home/docker PATH=$PATH bundle install --without test development; \
  sudo -u docker -E env HOME=/home/docker PATH=$PATH bundle clean --force; \
  yarn install --prod; \
  \
  # now some cleanup... \
  rm -rf \
    /home/docker/.bundle/cache \
    $GEM_HOME/cache \
    $GEM_HOME/bundler/gems/*/{.git,spec,test,features} \
    $GEM_HOME/gems/*/{spec,test,features} \
    `yarn cache dir` \
    /root/.node-gyp \
    /tmp/phantomjs \
    .yardoc \
    client_apps/canvas_quizzes/{tmp,node_modules} \
    config/locales/generated \
    gems/*/node_modules \
    gems/plugins/*/node_modules \
    log \
    public/dist/maps \
    public/doc/api/*.json \
    public/javascripts/translations \
    tmp-*.tmp'

RUN sudo chown -R docker app/stylesheets

USER docker
