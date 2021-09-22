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
fi

#
# This script is intended to build the Lacework Agent Data Collector into a UBI based container image.
#

# Agent version
version=4.3.0.5216
commit_hash=4.3.0.5216_2021-09-16_master_39524df4acaa71c119236b405a1510c8217c44f2
amd64_rpm_sha1=11a222ae245a2b0d99747ef18d91d9d4ec097432
arm64_rpm_sha1=1c7d6748c6813645527df2eca0e8d0049435ca47

pkgname=lacework
download_url="https://s3-us-west-2.amazonaws.com/www.lacework.net/download/${commit_hash}"

#max number of retries for install
max_retries=1

#retry install after x seconds
max_wait=5

ARG1=$1
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
		*oracleserver*)
			# need to switch lsb_dist to match yum repo URL
			lsb_dist="oraclelinux"
			dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
		;;
		*fedora*|centos*|*redhatenterprise*|*scientific*)
			dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
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
	else
		rpm_pkg_suffix="x86_64"
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
	export pkg_fullname="${pkgname}-${version}-1.${rpm_pkg_suffix}.rpm"
	export pkg_tmp_filename=$(mktemp_safe .rpm "/tmp/${pkg_fullname}")
	(set -x; $curl ${download_url}/${pkg_fullname} > ${pkg_tmp_filename})
	file_sha1=$(sha1sum ${pkg_tmp_filename} | cut -d " " -f 1)
	sha1_name="$arch"_rpm_sha1
	exp_sha1=$(eval "echo \${$sha1_name}")

	if [ "${exp_sha1}" != "${file_sha1}" ]; then
		echo "----------------------------------"
		echo "Download sha1 checksum failed, [${exp_sha1}] [${file_sha1}]"
		echo "----------------------------------"
		exit 700
	fi
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
		*fedora*|*centos*|*oraclelinux*|*redhatenterprise*|*amzn*|*amazon*|*scientific*)

			if [ "$lsb_dist" = "*fedora*" ] && [ "$dist_version" -ge "22" ]; then
				echo "Using dnf"
				install_pkg_cmd="dnf -y install ${pkg_tmp_filename}"
				install_retries
			else
				set +e
				if command_exists microdnf; then
					echo "Using microdnf and rpm"
					install_pkg_cmd="rpm -i ${pkg_tmp_filename}"
				else
					echo "Using yum"
					yum repolist | grep ^epel
					disable_epel=$?
					if [ "$disable_epel" = "0" ]; then
						echo "Disabling EPEL repository"
						disable_epel="--disablerepo=epel"
					else
						disable_epel=""
					fi
					install_pkg_cmd="yum -y install ${pkg_tmp_filename}"
				fi
				install_retries
			fi
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

do_install() {
	check_bash
	check_x64

	sh_c='sh -c'
	shell_prefix

	curl=''
	get_curl

	lsb_dist=''
	get_lsb_dist

	check_root_cert

	check_user_x64

	dist_version=''
	get_dist_version

	arch=''
	get_arch

	rpm_pkg_suffix=''

	# Check if this is a forked Linux distro
	check_forked

	echo "Installing on  $lsb_dist ($dist_version)"

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
