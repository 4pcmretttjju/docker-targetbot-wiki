FROM        perl:latest
MAINTAINER  Rick Dulton <sam.olsen11@gmail.com>

RUN cpanm --notest --configure-timeout=3600 HTML::TreeBuilder MediaWiki::API

COPY files/* /usr/src/targetbot/
RUN mkdir /usr/src/targetbot/TargetReport
RUN chown nobody: /usr/src/targetbot/TargetReport

WORKDIR /usr/src/targetbot

USER nobody
CMD [ "perl", "./wiki-updater.pl" ]
