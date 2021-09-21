#!/bin/sh
# Copyright 2014-2021 Lacework Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.
set -e

if [ -n "${DEBUG}" ]; then
	echo "Debug mode ON"
	set -x
	exit
fi

#
# This script is meant for quick & easy install via:
#    1. sudo sh -c "$(curl -sSL https://s3-us-west-2.amazonaws.com/www.lacework.net/download/4.3.0.5146_2021-09-13_master_36599af652b771c16f9e64f4cc3bf5d6ea8fe3b0/install.sh)"
#    or
#    1. "curl -sSL https://s3-us-west-2.amazonaws.com/www.lacework.net/download/4.3.0.5146_2021-09-13_master_36599af652b771c16f9e64f4cc3bf5d6ea8fe3b0/install.sh > /tmp/install.sh"
#    2. sudo sh /tmp/install.sh -U <serverurl>
#    Note: <serverurl> is the Lacework Server URL specific to your region.
#          if not provided, the US URL will be assumed
#    or
#    1. export LaceworkAccessToken=<accesstoken>
#    3. /usr/bin/docker run --name datacollector --net=host --pid=host --privileged --volume /:/laceworkfim:ro --volume /var/lib/lacework:/var/lib/lacework --volume /var/log:/var/log --volume /var/run:/var/run --volume /etc/passwd:/etc/passwd:ro --volume /etc/group:/etc/group:ro --env LaceworkAccessToken lacework/datacollector:latest

SYSTEMD_OVERRIDE=no
STRICT_MODE=no
FIM_ENABLE=enable
# Agent version
version=4.3.0.5146
commit_hash=4.3.0.5146_2021-09-13_master_36599af652b771c16f9e64f4cc3bf5d6ea8fe3b0
# These variables are deprecated and will be removed in the next release
deb_sha1=56ed0e210d855834ce914089f3468abdaec89201
rpm_sha1=c26ef40aae3452eca8acd2342c1ac53df1dbd68c
dc_sha1=
dc_musl_sha1=

amd64_deb_sha1=56ed0e210d855834ce914089f3468abdaec89201
amd64_rpm_sha1=c26ef40aae3452eca8acd2342c1ac53df1dbd68c
arm64_deb_sha1=516a5d1854af3581238f00ce014aa2345bb20e6c
arm64_rpm_sha1=f3ff905e083e3c7f8e73790976a93633f4e1afea
apk_sha1=18d9fdbb30a111d06a61596b4eefc0fa25e54d9b

pkgname=lacework
download_url="https://s3-us-west-2.amazonaws.com/www.lacework.net/download/${commit_hash}"
#max number of retries for install
max_retries=1
#retry install after x seconds
max_wait=5

ARG1=$1
usedocker=no
SERVER_URL=""
#default server url
lw_server_url="https://api.lacework.net"

# extra protection for mktemp: when it fails - returns fallback value
mktemp_safe() {
	TMP_FN=$(mktemp -u -t "XXXXXX")
	if [ "$TMP_FN" = "" ]; then
		echo $2
	else
		FN="${TMP_FN}${1}"
		touch ${FN}
		echo "${FN}"
	fi
}

check_bash() {
	if [ "$ARG1" = "" ];
	then
		if [ "$0" = "bash" ] ||  [ "$0" = "sh" ];
		then
			cat <<-EOF
			 ----------------------------------
			    Error:
			    This installer needs user input and was unable to read it.

			    Please run the installer using one of the following options:

			        1. sudo sh -c "\$(curl -sSL ${download_url}/install.sh)"

			    OR a two steps process to download the installer to /tmp and run it from there.

			        1. "curl -sSL ${download_url}/install.sh > /tmp/install.sh"
		        	2. sudo sh /tmp/install.sh
			 ----------------------------------
			EOF
			exit 100
		fi
	fi
}

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

# Check if this is a forked Linux distro
check_forked() {
	# Check for lsb_release command existence, it usually exists in forked distros
	if command_exists lsb_release; then
		# Check if the `-u` option is supported
		set +e
		lsb_release -a -u > /dev/null 2>&1
		lsb_release_exit_code=$?
		set -e

		# Check if the command has exited successfully, it means we're in a forked distro
		if [ "$lsb_release_exit_code" = "0" ]; then
			# Print info about current distro
			cat <<-EOF
			You're using '$lsb_dist' version '$dist_version'.
			EOF

			# Get the upstream release info
			lsb_dist=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'id' | cut -d ':' -f 2 | tr -d '[[:space:]]')
			dist_version=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'codename' | cut -d ':' -f 2 | tr -d '[[:space:]]')

			# Print info about upstream distro
			cat <<-EOF
			Upstream release is '$lsb_dist' version '$dist_version'.
			EOF
		fi
	fi
}

check_x64() {
	case "$(uname -m)" in
		*64)
			;;
		*)
			cat >&2 <<-'EOF'
			     ----------------------------------
			        Error: you are using a 32-bit kernel.
			        Lacework currently only supports 64-bit platforms.
			     ----------------------------------
			EOF
			exit 200
			;;
	esac
}

check_root_cert() {

	echo "Check Go Daddy root certificate"
GODADDY_ROOT_CERT=$(mktemp_safe .cert /tmp/godaddy.cert)
LW_INSTALLER_KEY=$(mktemp_safe .cert /tmp/installer_key.cert)
cat > ${GODADDY_ROOT_CERT} <<-'EOF'
-----BEGIN CERTIFICATE-----
MIIEfTCCA2WgAwIBAgIDG+cVMA0GCSqGSIb3DQEBCwUAMGMxCzAJBgNVBAYTAlVT
MSEwHwYDVQQKExhUaGUgR28gRGFkZHkgR3JvdXAsIEluYy4xMTAvBgNVBAsTKEdv
IERhZGR5IENsYXNzIDIgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTQwMTAx
MDcwMDAwWhcNMzEwNTMwMDcwMDAwWjCBgzELMAkGA1UEBhMCVVMxEDAOBgNVBAgT
B0FyaXpvbmExEzARBgNVBAcTClNjb3R0c2RhbGUxGjAYBgNVBAoTEUdvRGFkZHku
Y29tLCBJbmMuMTEwLwYDVQQDEyhHbyBEYWRkeSBSb290IENlcnRpZmljYXRlIEF1
dGhvcml0eSAtIEcyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv3Fi
CPH6WTT3G8kYo/eASVjpIoMTpsUgQwE7hPHmhUmfJ+r2hBtOoLTbcJjHMgGxBT4H
Tu70+k8vWTAi56sZVmvigAf88xZ1gDlRe+X5NbZ0TqmNghPktj+pA4P6or6KFWp/
3gvDthkUBcrqw6gElDtGfDIN8wBmIsiNaW02jBEYt9OyHGC0OPoCjM7T3UYH3go+
6118yHz7sCtTpJJiaVElBWEaRIGMLKlDliPfrDqBmg4pxRyp6V0etp6eMAo5zvGI
gPtLXcwy7IViQyU0AlYnAZG0O3AqP26x6JyIAX2f1PnbU21gnb8s51iruF9G/M7E
GwM8CetJMVxpRrPgRwIDAQABo4IBFzCCARMwDwYDVR0TAQH/BAUwAwEB/zAOBgNV
HQ8BAf8EBAMCAQYwHQYDVR0OBBYEFDqahQcQZyi27/a9BUFuIMGU2g/eMB8GA1Ud
IwQYMBaAFNLEsNKR1EwRcbNhyz2h/t2oatTjMDQGCCsGAQUFBwEBBCgwJjAkBggr
BgEFBQcwAYYYaHR0cDovL29jc3AuZ29kYWRkeS5jb20vMDIGA1UdHwQrMCkwJ6Al
oCOGIWh0dHA6Ly9jcmwuZ29kYWRkeS5jb20vZ2Ryb290LmNybDBGBgNVHSAEPzA9
MDsGBFUdIAAwMzAxBggrBgEFBQcCARYlaHR0cHM6Ly9jZXJ0cy5nb2RhZGR5LmNv
bS9yZXBvc2l0b3J5LzANBgkqhkiG9w0BAQsFAAOCAQEAWQtTvZKGEacke+1bMc8d
H2xwxbhuvk679r6XUOEwf7ooXGKUwuN+M/f7QnaF25UcjCJYdQkMiGVnOQoWCcWg
OJekxSOTP7QYpgEGRJHjp2kntFolfzq3Ms3dhP8qOCkzpN1nsoX+oYggHFCJyNwq
9kIDN0zmiN/VryTyscPfzLXs4Jlet0lUIDyUGAzHHFIYSaRt4bNYC8nY7NmuHDKO
KHAN4v6mF56ED71XcLNa6R+ghlO773z/aQvgSMO3kwvIClTErF0UZzdsyqUvMQg3
qm5vjLyb4lddJIGvl5echK1srDdMZvNhkREg5L4wn3qkKQmw4TRfZHcYQFHfjDCm
rw==
-----END CERTIFICATE-----
EOF
    reqsubstr="OK"

	if command_exists awk; then
		if command_exists openssl; then
			cert_path=`openssl version -d | grep OPENSSLDIR | awk -F: '{print $2}' | sed 's/"//g'`
			if [ -z "${cert_path}" ]; then
				cert_path="/etc/ssl"
			fi
			cert_ok=`openssl verify -x509_strict ${GODADDY_ROOT_CERT}`
			if [ ! -z "${cert_ok##*$reqsubstr*}" ];	then
				openssl x509 -noout -in ${GODADDY_ROOT_CERT} -pubkey > ${LW_INSTALLER_KEY}
				cert_ok=`awk -v cmd='openssl x509 -noout -pubkey | cmp -s ${LW_INSTALLER_KEY}; if [ $? -eq 0 ]; then echo "installed"; fi' '/BEGIN/{close(cmd)};{print | cmd}' < ${cert_path}/certs/ca-certificates.crt`
				if [ "${cert_ok}" != "installed" ]; then
					cat >&2 <<-'EOF'
					----------------------------------
						Error: this installer requires Go Daddy root certificate to be installed.
						Please ensure the root certificate is installed and retry.
					----------------------------------
					EOF
					if [ "${STRICT_MODE}" = "yes" ]; then
						rm -f ${GODADDY_ROOT_CERT}
						rm -f ${LW_INSTALLER_KEY}
						exit 300
					fi
				fi
			fi
		fi
	fi
	rm -f ${GODADDY_ROOT_CERT}
	rm -f ${LW_INSTALLER_KEY}
}

get_serverurl_from_cfg_file() {
	if command_exists awk; then
		if [ -f /var/lib/lacework/config/config.json ]; then
			config_url=$(grep -v "#" /var/lib/lacework/config/config.json)
			config_url=$(echo $config_url | awk 'BEGIN {RS=","} match($0, /serverurl([^,]+)/) { print substr( $0, RSTART, RLENGTH )}')
			config_url=$(echo $config_url | awk 'BEGIN{ORS=""}{print $0}')
			config_url=$(echo $config_url | sed 's/[\} ]//g')
			config_url=$(echo $config_url | awk 'BEGIN {FS="\""} {print $3}')
			if [ ! -z "${config_url}" ]; then
				echo "${config_url}"
				return
			fi
		fi
	fi
	echo ""
}

read_lw_server_url() {
	cfg_url=$(get_serverurl_from_cfg_file)
	if [ ! -z "${cfg_url}" ]; then
	echo "Using serverurl already set in local config: ${cfg_url}"
		lw_server_url=${cfg_url}
		return
	fi
	if [ ! -z "$SERVER_URL" ];
	then
		lw_server_url=$SERVER_URL
	fi
}

check_lw_connectivity() {
	lw_cfg_url="${lw_server_url}/upgrade/?name=datacollector&version=${version}"

	if [ "${STRICT_MODE}" = "no" ]; then
		set +e
	fi
	echo "Check connectivity to Lacework server"
	if command_exists awk; then
		cfg_url=$(get_serverurl_from_cfg_file)
		if [ ! -z "${cfg_url}" ]; then
			lw_cfg_url=${cfg_url}
		fi
		if command_exists curl; then
			response=`curl -o /dev/null -w "%{http_code}" -sSL ${lw_cfg_url}`
		elif command_exists wget; then
			response=`wget -SO- ${lw_cfg_url} 2>&1 | grep 'HTTP/' | awk '{print $(NF-1)}'`
		elif command_exists busybox && busybox --list-modules | grep -q wget; then
			response="500"
			busybox wget -O- ${lw_cfg_url} 2>&1 > /dev/null
			if [ $? == 0 ]; then
				response="200"
			fi
		fi
		if [ "${response}" != "200" ]; then
			cat >&2 <<-EOF
			----------------------------------
			Error: this installer needs the ability to contact $lw_cfg_url
			Please ensure this machine is able to connect to the network
			and/or configure correct proxy settings
			----------------------------------
			EOF
			if [ "${STRICT_MODE}" = "yes" ]; then
				exit 400
			fi
		fi
	fi
	if [ "${STRICT_MODE}" = "no" ]; then
		set -e
	fi
}

shell_prefix() {
	user=$(whoami)
	if [ "$user" != 'root' ]; then
		cat >&2 <<-'EOF'
				----------------------------------
				Error: this installer needs the ability to run commands as root.
				Please run the installer as root or with sudo.
				----------------------------------
		EOF
		exit 500
	fi
}

get_curl() {
	if command_exists curl; then
		curl='curl -sSL'
	elif command_exists wget; then
		curl='wget -qO-'
	elif command_exists busybox && busybox --list-modules | grep -q wget; then
		curl='busybox wget -qO-'
	fi
}

get_lsb_dist() {

	# perform some very rudimentary platform detection

	case "$usedocker" in
		yes)
			lsb_dist="usedocker"
			;;
		*)
			;;
	esac

	if [ -z "$lsb_dist" ] && command_exists lsb_release; then
		lsb_dist="$(lsb_release -si)"
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/lsb-release ]; then
		lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/debian_version ]; then
		lsb_dist='debian'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/fedora-release ]; then
		lsb_dist='fedora'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/oracle-release ]; then
		lsb_dist='oracleserver'
	fi
	if [ -z "$lsb_dist" ]; then
		if [ -r /etc/centos-release ] || [ -r /etc/redhat-release ]; then
			lsb_dist='centos'
		fi
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
 	if [ -z "$lsb_dist" ] && [ -r /etc/system-release ]; then
 		lsb_dist="$(cat /etc/system-release | cut -d " " -f 1)"
 	fi

	# Convert to all lower
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
}

check_user_x64() {
	case "$lsb_dist" in
		*ubuntu*|*debian*)
			case "$(dpkg --print-architecture)" in
				*64)
					;;
				*)
					cat >&2 <<-'EOF'
					     ----------------------------------
					        Error: Package manager (dpkg) does not support 64-bit binaries.
					        Lacework currently only supports 64-bit platforms.
					     ----------------------------------
					EOF
					exit 600
					;;
			esac
		;;
		*coreos*|usedocker)
		;;
		*fedora*|*centos*|*redhatenterprise*|*oracleserver*|*scientific*)
		;;
		*)
		;;
	esac
}

get_dist_version() {
	case "$lsb_dist" in
		*ubuntu*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;
		*debian*)
			dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
			case "$dist_version" in
				8)
					dist_version="jessie"
				;;
				7)
					dist_version="wheezy"
				;;
			esac
		;;
		*oracleserver*)
			# need to switch lsb_dist to match yum repo URL
			lsb_dist="oraclelinux"
			dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
		;;
		*fedora*|centos*|*redhatenterprise*|*scientific*)
			dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
		;;
		*coreos*|usedocker)
			dist_version="coreos"
		;;
		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;
	esac
}

get_pkg_suffix() {
	if [ "$arch" = "arm64" ]; then
		rpm_pkg_suffix="aarch64"
		deb_pkg_suffix="arm64"
	else
		rpm_pkg_suffix="x86_64"
		deb_pkg_suffix="amd64"
	fi
}

get_arch() {
	local archname=`uname -m`
	if [ "$archname" = "aarch64" ]; then
		arch="arm64"
	else
		arch="amd64"
	fi
}


download_pkg() {
	case "$lsb_dist" in
		*ubuntu*|*debian*)
			export pkg_fullname="${pkgname}_${version}_${deb_pkg_suffix}.deb"
			export pkg_tmp_filename=$(mktemp_safe .deb "/tmp/${pkg_fullname}")
			(set -x; $curl ${download_url}/${pkg_fullname} > ${pkg_tmp_filename})
			file_sha1=$(sha1sum ${pkg_tmp_filename} | cut -d " " -f 1)
			sha1_name="$arch"_deb_sha1
			exp_sha1=$(eval "echo \${$sha1_name}")
		;;
		*alpine*)
			export pkg_fullname="${pkgname}-${version}-r1.apk"
			export pkg_tmp_filename=$(mktemp_safe .apk "/tmp/${pkg_fullname}")
			(set -x; $curl ${download_url}/${pkg_fullname} > ${pkg_tmp_filename})
			file_sha1=$(sha1sum ${pkg_tmp_filename} | cut -d " " -f 1)
			exp_sha1=${apk_sha1}
		;;
		*coreos*|usedocker)
			(set -x; $curl ${download_url}/datacollector.service > /etc/systemd/system/datacollector.service)
		;;
		*)
			export pkg_fullname="${pkgname}-${version}-1.${rpm_pkg_suffix}.rpm"
			export pkg_tmp_filename=$(mktemp_safe .rpm "/tmp/${pkg_fullname}")
			(set -x; $curl ${download_url}/${pkg_fullname} > ${pkg_tmp_filename})
			file_sha1=$(sha1sum ${pkg_tmp_filename} | cut -d " " -f 1)
			sha1_name="$arch"_rpm_sha1
			exp_sha1=$(eval "echo \${$sha1_name}")
		;;
	esac
	if [ "${exp_sha1}" != "${file_sha1}" ]; then
		echo "----------------------------------"
		echo "Download sha1 checksum failed, [${exp_sha1}] [${file_sha1}]"
		echo "----------------------------------"
		exit 700
	fi
}

install_signed_apt() {
	lsb_ver=`lsb_release -r | cut -f2`
	lsb_rel=`lsb_release -c | cut -f2`
	lsb_distro=`lsb_release -i | cut -f2`
	if [ "$lsb_distro" = "Debian" ]; then
		lsb_ver=`lsb_release -r | cut -f2 | cut -d. -f1`
	fi
	( set -x; $sh_c "sleep 3; apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 18E76630; \
		add-apt-repository 'deb [arch=${deb_pkg_suffix}] ${download_url}/latest/DEB/$lsb_distro/$lsb_ver $lsb_rel main'; \
		apt-get update; apt-get install lacework" )
}

install_signed_rpm() {
	( set -x; $sh_c "sleep 3; \
		curl -sSL ${download_url}/latest/RPMS/${rpm_pkg_suffix}/lacework-prod.repo > /tmp/lacework-prod.repo.$$;\
		mv /tmp/lacework-prod.repo.$$ /etc/yum.repos.d/lacework-prod.repo; \
		microdnf install -y ${disable_epel} ${pkg_tmp_filename}")
}

install_retries() {
	set +e
	retries=0
	#wait only 3sec first time like other commands
	check_after=3
	while [ $retries -le $max_retries ]
	do
		if [ $retries -eq $max_retries ]; then
			echo "Failed to install ${install_pkg_cmd}"
			exit 1
		fi
		(set -x; $sh_c "sleep ${check_after}; ${install_pkg_cmd}" )
		if [ "$?" = "0" ];
		then
			break
		fi
		retries=$((retries+1))
		check_after=${max_wait}
		echo "Install retry $retries."
	done
	#revert back to global setting
	set -e
}

install_pkg() {

	# Run setup for each distro accordingly
	case "$lsb_dist" in
		'opensuse project'|*opensuse*|'suse linux'|sle[sd])
		install_pkg_cmd="zypper -n install ${pkg_tmp_filename}"
		install_retries
		;;
		*ubuntu*|*debian*)
			export DEBIAN_FRONTEND=noninteractive

			did_apt_get_update=
			apt_get_update() {
				if [ -z "$did_apt_get_update" ]; then
					install_pkg_cmd="apt-get -qq update"
					install_retries
					did_apt_get_update=1
				fi
			}

			# Set +e to make sure we do not fail if these commands fail, but capture the error
                        # On end-of-release versions (E.g. 13.10) apt-get update fails

			set +e
			apt_get_update
			install_pkg_cmd="dpkg -i ${pkg_tmp_filename}"
			install_retries
		;;
		*fedora*|*centos*|*oraclelinux*|*redhatenterprise*|*amzn*|*amazon*|*scientific*)

			if [ "$lsb_dist" = "*fedora*" ] && [ "$dist_version" -ge "22" ]; then
				echo "Using dnf"
				install_pkg_cmd="dnf -y install ${pkg_tmp_filename}"
				install_retries
			else
				echo "Using rpm"
				set +e
				microdnf repolist | grep ^epel
				disable_epel=$?
				if [ "$disable_epel" = "0" ]; then
					disable_epel="--disablerepo=epel"
				else
					disable_epel=""
				fi
				install_pkg_cmd="rpm -i ${pkg_tmp_filename}"
				install_retries
			fi
		;;
		*coreos*|usedocker)
			(set -x; systemctl stop datacollector.service)
			(set -x; systemctl daemon-reload)
			(set -x; systemctl enable datacollector.service)
			(set -x; systemctl start datacollector.service)
		;;
		*alpine*)
			install_pkg_cmd="apk add --allow-untrusted ${pkg_tmp_filename}"
			install_retries
		;;
		*)
		cat >&2 <<-EOF
		    ----------------------------------
		      Error: The platform '$lsb_dist' is not supported by this installer.

		             You can find the list of supported platforms at:
		             https://support.lacework.com/hc/en-us/articles/360005230014-Supported-Operating-Systems
		    ----------------------------------
		EOF
		exit 1
		;;
	esac
}

# Customized parameters
write_config() {

	if [ ! -f /var/lib/lacework/config/config.json ]
	then
		if [ "$ARG1" = "" ];
		then
			read -p "Please enter access token: " access_token
		else
			access_token=$ARG1
		fi
		if [ "$access_token" = "" ];
		then
			echo "Not a valid access_token"
			exit 800
		fi
		rbacTokenLen="1-30"
		LwTokenShort=`echo "$access_token" |cut -c${rbacTokenLen}`
		echo "Using access token : $LwTokenShort ..."
		echo "Using server url : $lw_server_url"
		echo "Writing configuration file"

		(set -x; $sh_c 'mkdir -p /var/lib/lacework/config')
		($sh_c 'echo "+ sh -c Writing config.json in /var/lib/lacework/config"')
		($sh_c "echo \"{\" > /var/lib/lacework/config/config.json")
		($sh_c "echo \" \\\"tokens\\\" : { \\\"AccessToken\\\" : \\\"${access_token}\\\" } \"    >> /var/lib/lacework/config/config.json")
		($sh_c "echo \" ,\\\"serverurl\\\" : \\\"${lw_server_url}\\\" \"    >> /var/lib/lacework/config/config.json")
		if [ "$FIM_ENABLE" = "disable" ]; then
			($sh_c "echo \" ,\\\"fim\\\" : { \\\"mode\\\" : \\\"${FIM_ENABLE}\\\" } \"    >> /var/lib/lacework/config/config.json")
		fi
		($sh_c "echo \"}\" >> /var/lib/lacework/config/config.json")
	else
		echo "Skipping writing config since a config file already exists"
	fi
}


do_install() {
	check_bash
	check_x64

	sh_c='sh -c'
	shell_prefix

	curl=''
	get_curl

	lsb_dist=''
	get_lsb_dist

	read_lw_server_url

	check_lw_connectivity

	check_root_cert

	check_user_x64

	dist_version=''
	get_dist_version

	arch=''
	get_arch

	rpm_pkg_suffix=''
	deb_pkg_suffix=''
	get_pkg_suffix

	# Check if this is a forked Linux distro
	check_forked

	echo "Installing on  $lsb_dist ($dist_version)"

	write_config

	pkg_fullname=''
	download_pkg
	install_pkg

	echo "Lacework successfully installed"
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
while getopts "SFOhU:" arg; do
  case $arg in
    h)
	cat >&2 <<-'EOF'
	     ----------------------------------
	     Usage: sudo install.sh -h [-S] [-O] [-F]
	            -h: usage banner
	                [Optional Parameters]
	            -F: disable FIM
	            -S: enable strict mode
	            -O: filter auditd related messages going to system journal
	            -U: server url where Agent sends data
	     ----------------------------------
	EOF
	exit 0
     ;;
    O)
      SYSTEMD_OVERRIDE=yes
      shift
      ;;
    F)
      FIM_ENABLE=disable
      shift
      ;;
    S)
      STRICT_MODE=yes
      shift
	  ;;
    U)
      if [ -z "${OPTARG}" ]; then
         echo "server url not provided"
         exit 1
      fi

      #in case of a mismatch the exit status of below expression is 1, and set -e will make the script exit.
      #hence the '|| true' at the end.
      match=$(echo "${OPTARG}" | grep -E "^https://.*\.lacework.net$") || true
      if [ -z $match ]; then
        echo "Please provide a valid serverurl in lacework.net domain"
        exit 1
      fi

      if [ ! -z "${SERVER_URL}" ]; then
         if [ "${SERVER_URL}" != "${OPTARG}" ]; then
             echo "Provided serverurl ${OPTARG} is incorrect for your region, trying ${SERVER_URL}"
         fi
         lw_server_url=${SERVER_URL}
      else
         lw_server_url=${OPTARG}
      fi
      shift 2
      ;;
  esac
done

ARG1=$1
if [ ! -z "${ARG1}" ]; then
   ARG1=`echo ${ARG1} | grep -E '^[[:alnum:]][-[:alnum:]]{0,55}[[:alnum:]]$'`
fi

do_install

if [ "${SYSTEMD_OVERRIDE}" = "yes" ]; then
	if command_exists systemctl; then
	        systemctl mask systemd-journald-audit.socket
	        systemctl restart systemd-journald
	fi
fi

exit 0
