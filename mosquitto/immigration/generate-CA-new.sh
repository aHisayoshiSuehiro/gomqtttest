#!/bin/bash -eu
#(@)generate-CA.sh - Create CA key-pair and server key-pair signed by CA

# Copyright (c) 2013-2016 Jan-Piet Mens <jpmens()gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of mosquitto nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

#
# Usage:
#	./generate-CA.sh		creates ca.crt and server.{key,crt}
#	./generate-CA.sh hostname	creates hostname.{key,crt}
#	./generate-CA.sh client email	creates email.{key,crt}
#
# Set the following optional environment variables before invocation
# to add the specified IP addresses and/or hostnames to the subjAltName list
# These contain white-space-separated values
#
#	IPLIST="172.13.14.15 192.168.1.1"
#	HOSTLIST="a.example.com b.example.com"

set -e

export LANG=C

kind=server

CA_ORG='/C=JP/ST=Tokyo/O=KONICA MINOLTA, INC./OU=IoT Service Platform Development Operations/emailAddress=nobody@example.net'
if [ $# -ne 2 ]; then
	kind=server
	host=$(hostname -f)
	if [ -n "$1" ]; then
		host="$1"
	fi
	SERVER="${OUTDIR}/${host}"
	SERVERKEY="${PVTKEYDIR}/${host}"
	SERVER_DN="/CN=${host}$CA_ORG"
else
	kind=client
	CLIENT="$2"
fi

[ -z "$USER" ] && USER=root

# A space-separated list of alternate hostnames (subjAltName)
# may be empty ""
CA_DN="/CN=An MQTT broker${CA_ORG}"
CACERT=${CADIR}/${CANAME}
CAKEY=${PVTKEYDIR}/${CANAME}
keybits=2048
openssl=$(which openssl)
MOSQUITTOUSER=${MOSQUITTOUSER:=$USER}

# Signature Algorithm. To find out which are supported by your
# version of OpenSSL, run `openssl dgst -help` and set your
# signature algorithm here. For example:
#
#	defaultmd="-sha256"
#
defaultmd="-sha512"

function maxdays() {
	nowyear=$(date +%Y)
	years=$(expr 2032 - $nowyear)
	days=$(expr $years '*' 365)

	echo $days
}

function getipaddresses() {
	/sbin/ifconfig |
		grep -v tunnel |
		sed -En '/inet6? /p' |
		sed -Ee 's/inet6? (addr:)?//' |
		awk '{print $1;}' |
		sed -e 's/[%/].*//' |
		egrep -v '(::1|127\.0\.0\.1)'	# omit loopback to add it later
}


function addresslist() {

	ALIST=""
	for a in $(getipaddresses); do
		ALIST="${ALIST}IP:$a,"
	done
	ALIST="${ALIST}IP:127.0.0.1,IP:::1,"

	ALIST="${ALIST}DNS:localhost"
	echo $ALIST

}

days=$(maxdays)

if [ $kind == 'server' ]; then

	#   ____
	#  / ___|  ___ _ ____   _____ _ __
	#  \___ \ / _ \ '__\ \ / / _ \ '__|
	#   ___) |  __/ |   \ V /  __/ |
	#  |____/ \___|_|    \_/ \___|_|
	#

	if [ ! -f $SERVER.key ]; then
		echo "--- Creating server key and signing request"
		$openssl genrsa -out $SERVERKEY.key $keybits
		$openssl req -new $defaultmd \
			-out $SERVER.csr \
			-key $SERVERKEY.key \
			-subj "${SERVER_DN}"
		chmod 400 $SERVERKEY.key
		chown $MOSQUITTOUSER $SERVERKEY.key
	fi

	if [ -f $SERVER.csr -a ! -f $SERVER.crt ]; then

		# There's no way to pass subjAltName on the CLI so
		# create a cnf file and use that.

		CNF=`mktemp /tmp/cacnf.XXXXXXXX` || { echo "$0: can't create temp file" >&2; exit 1; }
		sed -e 's/^.*%%% //' > $CNF <<\!ENDconfig
		%%% [ JPMextensions ]
		%%% basicConstraints        = critical,CA:false
		%%% nsCertType              = server
		%%% keyUsage                = nonRepudiation, digitalSignature, keyEncipherment
		%%% nsComment               = "Broker Certificate"
		%%% subjectKeyIdentifier    = hash
		%%% authorityKeyIdentifier  = keyid,issuer:always
		%%% subjectAltName          = $ENV::SUBJALTNAME
		%%% # issuerAltName           = issuer:copy
		%%% ## nsCaRevocationUrl       = http://mqttitude.org/carev/
		%%% ## nsRevocationUrl         = http://mqttitude.org/carev/
		%%% certificatePolicies     = ia5org,@polsection
		%%% 
		%%% [polsection]
		%%% policyIdentifier	    = 1.3.5.8
		%%% CPS.1		    = "http://localhost"
		%%% userNotice.1	    = @notice
		%%% 
		%%% [notice]
		%%% explicitText            = "This CA is for a local MQTT broker installation only"
		%%% organization            = "OwnTracks"
		%%% noticeNumbers           = 1

!ENDconfig

		SUBJALTNAME="$(addresslist)"
		export SUBJALTNAME		# Use environment. Because I can. ;-)

		echo "--- Creating and signing server certificate"
		$openssl x509 -req $defaultmd \
			-in $SERVER.csr \
			-CA $CACERT.crt \
			-CAkey ${CAKEY}.key \
			-CAcreateserial \
			-CAserial "${CADIR}/ca.srl" \
			-out $SERVER.crt \
			-days $days \
			-extfile ${CNF} \
			-extensions JPMextensions

		rm -f $CNF
		chmod 444 $SERVER.crt
		chown $MOSQUITTOUSER $SERVER.crt
	fi
else
	#    ____ _ _            _
	#   / ___| (_) ___ _ __ | |_
	#  | |   | | |/ _ \ '_ \| __|
	#  | |___| | |  __/ | | | |_
	#   \____|_|_|\___|_| |_|\__|
	#

	if [ ! -f $CLIENT.key ]; then
		echo "--- Creating client key and signing request"
		$openssl genrsa -out $CLIENT.key $keybits

		CNF=`mktemp /tmp/cacnf-req.XXXXXXXX` || { echo "$0: can't create temp file" >&2; exit 1; }
		# Mosquitto's use_identity_as_username takes the CN attribute
		# so we're populating that with the client's name
		sed -e 's/^.*%%% //' > $CNF <<!ENDClientconfigREQ
		%%% [ req ]
		%%% distinguished_name	= req_distinguished_name
		%%% prompt			= no
		%%% output_password		= secret
		%%% 
		%%% [ req_distinguished_name ]
		%%% # O                       = OwnTracks
		%%% # OU                      = MQTT
		%%% # CN                      = Suzie Smith
		%%% CN                        = $CLIENT
		%%% # emailAddress            = $CLIENT
!ENDClientconfigREQ

		$openssl req -new $defaultmd \
			-out $CLIENT.csr \
			-key $CLIENT.key \
			-config $CNF
		chmod 400 $CLIENT.key
	fi

	if [ -f $CLIENT.csr -a ! -f $CLIENT.crt ]; then

		CNF=`mktemp /tmp/cacnf-cli.XXXXXXXX` || { echo "$0: can't create temp file" >&2; exit 1; }
		sed -e 's/^.*%%% //' > $CNF <<\!ENDClientconfig
		%%% [ JPMclientextensions ]
		%%% basicConstraints        = critical,CA:false
		%%% subjectAltName          = email:copy
		%%% nsCertType              = client,email
		%%% extendedKeyUsage        = clientAuth,emailProtection
		%%% keyUsage                = digitalSignature, keyEncipherment, keyAgreement
		%%% nsComment               = "Client Broker Certificate"
		%%% subjectKeyIdentifier    = hash
		%%% authorityKeyIdentifier  = keyid,issuer:always

!ENDClientconfig

		SUBJALTNAME="$(addresslist)"
		export SUBJALTNAME		# Use environment. Because I can. ;-)

		echo "--- Creating and signing client certificate"
		$openssl x509 -req $defaultmd \
			-in $CLIENT.csr \
			-CA $CACERT.crt \
			-CAkey ${CAKEY}.key \
			-CAcreateserial \
			-CAserial "${CADIR}/ca.srl" \
			-out $CLIENT.crt \
			-days $days \
			-extfile ${CNF} \
			-extensions JPMclientextensions

		rm -f $CNF
		chmod 444 $CLIENT.crt
	fi
fi