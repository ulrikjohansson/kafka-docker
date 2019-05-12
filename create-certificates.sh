#!/bin/bash

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 ca"
    echo "       $0 jks <name>"
    echo "       $0 pem <name"
    exit 1
fi

OP=$1

OU="OU=${OU:-docker}"
O="O=${O:-docker}"
#L=${L:-L=Stockholm}
C="C=${C:-SE}"

emailAddress=${emailAddress:-docker@docker.docker}

PW=${PW:-password}
CAPW=${CAPW:-password}

EXPIRE_DAYS=${EXPIRE_DAYS:=365}

DEST=${DEST:=./certificates}

if [ ! -d $DEST ]; then
    mkdir -p $DEST
fi

CA_KEY="$DEST/ca.key"
CA_CRT="$DEST/ca.crt"
CA_SRL="$DEST/ca.srl"

if [ "$OP" == "ca" ]; then
        echo "############################"
        echo "#         Create CA        #"
        echo "############################"
        openssl req -new -x509 -keyout $CA_KEY -out $CA_CRT -days $EXPIRE_DAYS -subj "/CN=kafka.docker.ca/emailAddress=$emailAddress/$OU/$O/$C" -passin pass:$PW -passout pass:$PW
else
        if [ "$#" -ne 2 ]; then
                echo "Usage: $OP $2 <name>"
                exit 1
        elif [ ! -f $CA_KEY -o ! -f $CA_CRT ]; then
                echo "You need a CA"
                echo "Usage: $0 ca"
                exit 1
        elif [ "$OP" == "jks" ] || [ "$OP" == "pem" ]; then
                CA_INFO=$(openssl x509 -in $CA_CRT -text |grep 'Issuer:' | tr -d '[:space:]')
                echo "###############################"
                echo "#  Create Client Certificate  #"
                echo "# $CA_INFO"
                echo "###############################"

                CN=$2

                echo "Name: $CN"

                DEST_PATH="$DEST/$CN"
                DEST_FILENAME="$DEST_PATH/client"

                if [ ! -d $DEST_PATH ]; then
                        mkdir $DEST_PATH
                fi

                if [ ! -f $DEST_FILENAME.key ] || [ ! -f $DEST_FILENAME.pem ]; then
                        openssl genrsa -des3 -passout "pass:$PW" -out $DEST_FILENAME.key 1024
                        openssl req -passin "pass:$PW" -key $DEST_FILENAME.key -new -out $DEST_FILENAME.csr  -subj "/CN=$CN/emailAddress=$emailAddress/$OU/$O/$C"
                        openssl x509 -req -passin "pass:$CAPW" -in $DEST_FILENAME.csr -days $EXPIRE_DAYS -CA $CA_CRT -CAkey $CA_KEY -CAcreateserial -CAserial $DEST_PATH/ca.srl -out $DEST_FILENAME.crt

                        rm $DEST_FILENAME.csr
                        rm $DEST_PATH/ca.srl
                fi

                if [ "$OP" == "jks" ]; then
                        KSTORE=$DEST_PATH/keystore.jks
                        TSTORE=$DEST_PATH/truststore.jks

                        openssl pkcs12 -export -in $DEST_FILENAME.crt -inkey $DEST_FILENAME.key -name $CN -out $DEST_FILENAME.p12 -passin "pass:$PW" -passout "pass:$PW"

                        keytool -importkeystore -deststorepass $PW -destkeystore $KSTORE -deststoretype PKCS12 -srckeystore $DEST_FILENAME.p12 -srcstoretype PKCS12 -srcstorepass $PW
                        keytool -storetype pkcs12  -trustcacerts -noprompt -keystore $KSTORE -alias CARoot -import -file $CA_CRT -storepass $PW -keypass $PW

                        keytool -storetype pkcs12 -trustcacerts -noprompt -keystore $DEST_PATH/truststore.jks -alias CARoot -import -file $CA_CRT -storepass $PW -keypass $PW
                fi

        else
                echo "Invalid operation"
                exit 1
        fi
fi
