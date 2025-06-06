# muzso: we use Ubuntu (instead of Debian), because it has MySQL 5.7.* packages for ARM architecture too
FROM ubuntu:noble

# muzso: this is partly based off:
# - the most recent Debian based Dockerfile: https://github.com/docker-library/mysql/blob/master/8.0/Dockerfile.debian
# - the last Debian based 5.7.* state: https://github.com/docker-library/mysql/tree/eb1850601849ef7ef77a23f017a20debc95d597c/5.7

# muzso: MySQL 5.* is not in Ubuntu noble.
# We've to use the ones from bionic.
RUN set -eux; \
	apt-mark showmanual > "/tmp/apt_manual_packages.txt"; \
	newsrc="$(sed -r "s#noble#bionic#g" "/etc/apt/sources.list.d/ubuntu.sources")"; \
	echo "$newsrc" >> "/etc/apt/sources.list.d/ubuntu.sources"; \
	{ \
		echo "Package: *mysql*"; \
		echo "Pin: release n=bionic"; \
		echo "Pin-Priority: 600"; \
	} > "/etc/apt/preferences.d/bionic";

# persistent / runtime deps
# add gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.17
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates gnupg wget; \
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	# testing that gosu actually works
	gosu nobody true

RUN mkdir /docker-entrypoint-initdb.d

ENV MYSQL_MAJOR 5.7

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		mysql-server-${MYSQL_MAJOR} \
	; \
	echo "mysql-server-${MYSQL_MAJOR}" >> "/tmp/apt_manual_packages.txt"; \
	# comment out bind-address in /etc/mysql/mysql.conf.d/mysqld.cnf
	# so we can change its value in /etc/mysql/conf.d/docker.cnf
	# (note: the latter is evaluated sooner, this mysql.conf.d/mysqld.cnf overrides whatever is in conf.d/docker.cnf)
	sed -Ei "s/^([[:space:]]*bind-address[[:space:]]*=)/#&/" /etc/mysql/mysql.conf.d/mysqld.cnf; \
	# tzdata is required by MySQL DB setup
	echo "tzdata" >> "/tmp/apt_manual_packages.txt"; \
	apt-mark auto ".*" > /dev/null; \
	apt-get install -y --no-install-recommends $(cat "/tmp/apt_manual_packages.txt"); \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	rm "/tmp/apt_manual_packages.txt"; \
	# the "/var/lib/mysql" stuff here is because the mysql-server postinst doesn't have an explicit way to disable the mysql_install_db codepath besides having a database already "configured" (ie, stuff in /var/lib/mysql/mysql)
	rm -rf /var/lib/mysql && mkdir -p /var/lib/mysql /var/run/mysqld; \
	chown -R mysql:mysql /var/lib/mysql /var/run/mysqld; \
	# ensure that /var/run/mysqld (used for socket and lock files) is writable regardless of the UID our mysqld instance ends up having at runtime
	chmod 1777 /var/run/mysqld /var/lib/mysql; \
	# comment out a few problematic configuration values
	find /etc/mysql/ -type f -name "*.cnf" -print0 \
		| xargs -0 grep -lZE "^log_error" \
		| xargs -rt -0 sed -Ei "s/^log_error/#&/" \
	;

VOLUME /var/lib/mysql

# Config files
COPY conf.d/ /etc/mysql/conf.d/
COPY docker-entrypoint.sh /usr/local/bin/
RUN set -eux; \
	# backwards compat \
	ln -s /usr/local/bin/docker-entrypoint.sh /entrypoint.sh; \
	chmod a+rx /usr/local/bin/*.sh;
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306 33060
CMD ["mysqld"]
