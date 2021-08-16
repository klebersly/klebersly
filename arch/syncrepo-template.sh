#!/bin/bash
#
########
#
# Copyright © 2014-2019 Florian Pritz <bluewind@xinu.at>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.
#
########
#
# This is a simple mirroring script. To save bandwidth it first checks a
# timestamp via HTTP and only runs rsync when the timestamp differs from the
# local copy. As of 2016, a single rsync run without changes transfers roughly
# 6MiB of data which adds up to roughly 250GiB of traffic per month when rsync
# is run every minute. Performing a simple check via HTTP first can thus save a
# lot of traffic.

# Directory where the repo is stored locally. Example: /srv/repo
target="/archiso"

# Lockfile path
lock="/var/lock/syncrepo.lck"

# If you want to limit the bandwidth used by rsync set this.
# Use 0 to disable the limit.
# The default unit is KiB (see man rsync /--bwlimit for more)
bwlimit=5000

# The source URL of the mirror you want to sync from.
# If you are a tier 1 mirror use rsync.archlinux.org, for example like this:
# rsync://rsync.archlinux.org/ftp_tier1
# Otherwise chose a tier 1 mirror from this list and use its rsync URL:
# https://www.archlinux.org/mirrors/
source_url='rsync://archlinux.c3sl.ufpr.br/archlinux/'

# An HTTP(S) URL pointing to the 'lastupdate' file on your chosen mirror.
# If you are a tier 1 mirror use: https://rsync.archlinux.org/lastupdate
# Otherwise use the HTTP(S) URL from your chosen mirror.
lastupdate_url='http://archlinux.c3sl.ufpr.br/lastupdate'

#### END CONFIG

[ ! -d "${target}" ] && mkdir -p "${target}"

exec 9>"${lock}"
flock -n 9 || exit

# Cleanup any temporary files from old run that might remain.
# Note: You can skip this if you have rsync newer than 3.2.3
# not affected by https://github.com/WayneD/rsync/issues/192
find "${target}" -name '.~tmp~' -exec rm -r {} +

rsync_cmd() {
	local -a cmd=(rsync -rlptH --safe-links --delete-delay --delay-updates
		"--timeout=600" "--contimeout=60" --no-motd)

	if stty &>/dev/null; then
		cmd+=(-h -v --progress)
	else
		cmd+=(--quiet)
	fi

	if ((bwlimit>0)); then
		cmd+=("--bwlimit=$bwlimit")
	fi

	"${cmd[@]}" "$@"
}


# if we are called without a tty (cronjob) only run when there are changes
if ! tty -s && [[ -f "$target/lastupdate" ]] && diff -b <(curl -Ls "$lastupdate_url") "$target/lastupdate" >/dev/null; then
	# keep lastsync file in sync for statistics generated by the Arch Linux website
	rsync_cmd "$source_url/lastsync" "$target/lastsync"
	exit 0
fi

rsync_cmd \
	--exclude='*.links.tar.gz*' \
	--exclude='/other' \
	--exclude='/sources' \
	"${source_url}" \
	"${target}"
