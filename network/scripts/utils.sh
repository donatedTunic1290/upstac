#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This is a collection of bash functions used by different scripts

ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/upstac.com/orderers/orderer.upstac.com/msp/tlscacerts/tlsca.upstac.com-cert.pem
PEER0_HOSPITALA_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/hospitalA.upstac.com/peers/peer0.hospitalA.upstac.com/tls/ca.crt
PEER0_HOSPITALB_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/hospitalB.upstac.com/peers/peer0.hospitalB.upstac.com/tls/ca.crt
PEER0_GOVERNMENT_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/government.upstac.com/peers/peer0.government.upstac.com/tls/ca.crt


# verify the result of the end-to-end test
verifyResult() {
  if [ "$1" -ne 0 ]; then
    echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
    echo "========= ERROR !!! FAILED to execute Bootstrap ==========="
    echo
    exit 1
  fi
}

# Set OrdererOrg.Admin globals
setOrdererGlobals() {
  CORE_PEER_LOCALMSPID="OrdererMSP"
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/upstac.com/orderers/orderer.upstac.com/msp/tlscacerts/tlsca.upstac.com-cert.pem
  CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/upstac.com/users/Admin@upstac.com/msp
}

setGlobals() {
  PEER=$1
  ORG=$2
  if [ "$ORG" == 'hospitalA' ]; then
    CORE_PEER_LOCALMSPID="hospitalAMSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_HOSPITALA_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/hospitalA.upstac.com/users/Admin@hospitalA.upstac.com/msp
    if [ "$PEER" -eq 0 ]; then
      CORE_PEER_ADDRESS=peer0.hospitalA.upstac.com:7051
    else
      CORE_PEER_ADDRESS=peer1.hospitalA.upstac.com:8051
    fi
  elif [ "$ORG" == 'hospitalB' ]; then
    CORE_PEER_LOCALMSPID="hospitalBMSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_HOSPITALB_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/hospitalB.upstac.com/users/Admin@hospitalB.upstac.com/msp
    if [ "$PEER" -eq 0 ]; then
      CORE_PEER_ADDRESS=peer0.hospitalB.upstac.com:9051
    fi
    if [ "$PEER" -eq 1 ]; then
      CORE_PEER_ADDRESS=peer1.hospitalB.upstac.com:10051
    fi
  elif [ "$ORG" == 'government' ]; then
    CORE_PEER_LOCALMSPID="governmentMSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_GOVERNMENT_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/government.upstac.com/users/Admin@government.upstac.com/msp
    if [ "$PEER" -eq 0 ]; then
      CORE_PEER_ADDRESS=peer0.government.upstac.com:11051
    fi
    if [ "$PEER" -eq 1 ]; then
      CORE_PEER_ADDRESS=peer1.government.upstac.com:12051
    fi
  elif [ "$ORG" == 'insurance' ]; then
    CORE_PEER_LOCALMSPID="insuranceMSP"
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/insurance.upstac.com/users/Admin@insurance.upstac.com/msp
    if [ "$PEER" -eq 0 ]; then
      CORE_PEER_ADDRESS=peer0.insurance.upstac.com:21051
    fi
    if [ "$PEER" -eq 1 ]; then
      CORE_PEER_ADDRESS=peer1.insurance.upstac.com:22051
    fi

  else
    echo "================== ERROR !!! ORG Unknown =================="
  fi
}

updateAnchorPeers() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer channel update -o orderer.upstac.com:7050 -c "$CHANNEL_NAME" -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx >&log.txt
    res=$?
    set +x
  else
    set -x
    peer channel update -o orderer.upstac.com:7050 -c "$CHANNEL_NAME" -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls "$CORE_PEER_TLS_ENABLED" --cafile $ORDERER_CA >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Anchor peer update failed"
  echo "===================== Anchor peers updated for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME' ===================== "
  sleep "$DELAY"
  echo
}

## Sometimes Join takes time hence RETRY at least 5 times
joinChannelWithRetry() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"

  set -x
  peer channel join -b "$CHANNEL_NAME".block >&log.txt
  res=$?
  set +x
  cat log.txt
  if [ $res -ne 0 -a "$COUNTER" -lt "$MAX_RETRY" ]; then
    COUNTER=$(expr "$COUNTER" + 1)
    echo "peer${PEER}.${ORG} failed to join the channel, Retry after $DELAY seconds"
    sleep "$DELAY"
    joinChannelWithRetry "$PEER" "$ORG"
  else
    COUNTER=1
  fi
  verifyResult $res "After $MAX_RETRY attempts, peer${PEER}.${ORG} has failed to join channel '$CHANNEL_NAME' "
}

# packageChaincode VERSION PEER ORG
packageChaincode() {
  VERSION=$1
  PEER=$2
  ORG=$3
  setGlobals "$PEER" "$ORG"
  set -x
  peer lifecycle chaincode package upstac.tar.gz --path ${CC_SRC_PATH} --lang ${CC_RUNTIME_LANGUAGE} --label upstac_${VERSION} >&log.txt
  res=$?
  set +x
  cat log.txt
  verifyResult $res "Chaincode packaging on peer${PEER}.${ORG} has failed"
  echo "===================== Chaincode is packaged on peer${PEER}.${ORG} ===================== "
  echo
}

installChaincode() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"
  set -x
  peer lifecycle chaincode install upstac.tar.gz >&log.txt
  res=$?
  set +x
  cat log.txt
  verifyResult $res "Chaincode installation on peer${PEER}.${ORG} has failed"
  echo "===================== Chaincode is installed on peer${PEER}.${ORG} ===================== "
  echo
}

# queryInstalled PEER ORG
queryInstalled() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"
  set -x
  peer lifecycle chaincode queryinstalled >&log.txt
  res=$?
  set +x
  cat log.txt
  PACKAGE_ID=`sed -n '/Package/{s/^Package ID: //; s/, Label:.*$//; p;}' log.txt`
  verifyResult $res "Query installed on peer${PEER}.${ORG} has failed"
  echo PackageID For Chaincode Definition is ${PACKAGE_ID}
  echo "===================== Chaincode Package installed successfully on peer${PEER}.${ORG} ===================== "
  echo
}

# approveForMyOrg VERSION PEER ORG
approveForMyOrg() {
  VERSION=$1
  PEER=$2
  ORG=$3
  setGlobals "$PEER" "$ORG"

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer lifecycle chaincode approveformyorg --channelID $CHANNEL_NAME --name upstac --version ${VERSION} --init-required --package-id ${PACKAGE_ID} --sequence 1 --waitForEvent >&log.txt
    set +x
  else
    set -x
    peer lifecycle chaincode approveformyorg --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA --channelID $CHANNEL_NAME --name upstac --version ${VERSION} --init-required --package-id ${PACKAGE_ID} --sequence 1 --waitForEvent >&log.txt
    set +x
  fi
  cat log.txt
  verifyResult $res "Chaincode definition approved on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' failed"
  echo "===================== Chaincode definition approved on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

# commitChaincodeDefinition VERSION PEER ORG (PEER ORG)...
commitChaincodeDefinition() {
  VERSION=$1
  shift
  parsePeerConnectionParameters $@
  res=$?
  verifyResult $res "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer lifecycle chaincode commit -o orderer.upstac.com:7050 --channelID $CHANNEL_NAME --name upstac $PEER_CONN_PARMS --version ${VERSION} --sequence 1 --init-required >&log.txt
    res=$?
    set +x
  else
    set -x
    peer lifecycle chaincode commit -o orderer.upstac.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA --channelID $CHANNEL_NAME --name upstac $PEER_CONN_PARMS --version ${VERSION} --sequence 1 --init-required >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Chaincode definition commit failed on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' failed"
  echo "===================== Chaincode definition committed on channel '$CHANNEL_NAME' ===================== "
  echo
}

instantiateChaincode() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"
  VERSION=$3

  # while 'peer chaincode' command can get the orderer endpoint from the peer
  # (if join was successful), let's supply it directly as we know it using
  # the "-o" option
  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer chaincode instantiate -o orderer.upstac.com:7050 -C "$CHANNEL_NAME" -n common -l "${LANGUAGE}" -v "${VERSION}" -c '{"Args":["org.upstac.user:instantiate"]}' -P "OR ('hospitalAMSP.member','hospitalBMSP.member')" >&log.txt
    res=$?
    set +x
  else
    set -x
    peer chaincode instantiate -o orderer.upstac.com:7050 --tls "$CORE_PEER_TLS_ENABLED" --cafile $ORDERER_CA -C $CHANNEL_NAME -n common -l ${LANGUAGE} -v ${VERSION} -c '{"Args":["org.upstac.user:instantiate"]}' -P "OR ('hospitalAMSP.member','hospitalBMSP.member')" >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Chaincode instantiation on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' failed"
  echo "===================== Chaincode is instantiated on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

installChaincodeInsurance() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"
  VERSION=$3
  set -x
  peer chaincode install -n insure -v "${VERSION}" -l "${LANGUAGE}" -p "${CC_SRC_PATH}" >&log.txt
  res=$?
  set +x
  cat log.txt
  verifyResult $res "Chaincode installation on peer${PEER}.${ORG} has failed"
  echo "===================== Chaincode is installed on peer${PEER}.${ORG} ===================== "
  echo
}

instantiateChaincodeInsurance() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"
  VERSION=$3

  # while 'peer chaincode' command can get the orderer endpoint from the peer
  # (if join was successful), let's supply it directly as we know it using
  # the "-o" option
  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer chaincode instantiate -o orderer.upstac.com:7050 -C "$CHANNEL_NAME" -n insure -l "${LANGUAGE}" -v "${VERSION}" -c '{"Args":["org.upstac.insurance:instantiate"]}' -P "OR ('hospitalAMSP.member','insuranceMSP.member')" >&log.txt
    res=$?
    set +x
  else
    set -x
    peer chaincode instantiate -o orderer.upstac.com:7050 --tls "$CORE_PEER_TLS_ENABLED" --cafile $ORDERER_CA -C $CHANNEL_NAME -n insure -l ${LANGUAGE} -v ${VERSION} -c '{"Args":["org.upstac.insurance:instantiate"]}' -P "OR ('hospitalAMSP.member','insuranceMSP.member')" >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Chaincode instantiation on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' failed"
  echo "===================== Chaincode is instantiated on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

joinChannelWithRetryInsurance() {
  PEER=$1
  ORG=$2
  setGlobals "$PEER" "$ORG"

  set -x
  peer channel join -b "$CHANNEL_NAME".block >&log.txt
  res=$?
  set +x
  cat log.txt
  if [ $res -ne 0 -a "$COUNTER" -lt "$MAX_RETRY" ]; then
    COUNTER=$(expr "$COUNTER" + 1)
    echo "peer${PEER}.${ORG} failed to join the channel, Retry after $DELAY seconds"
    sleep "$DELAY"
    joinChannelWithRetry "$PEER" "$ORG"
  else
    COUNTER=1
  fi
  verifyResult $res "After $MAX_RETRY attempts, peer${PEER}.${ORG} has failed to join channel '$CHANNEL_NAME' "
}

upgradeChaincode() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG
  VERSION=$3

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer chaincode upgrade -o orderer.upstac.com:7050 -C $CHANNEL_NAME -n common -l ${LANGUAGE} -v ${VERSION} -p ${CC_SRC_PATH} -c '{"Args":["org.upstac.user:instantiate"]}' -P "OR ('hospitalAMSP.member','hospitalBMSP.member')" >&log.txt
    res=$?
    set +x
  else
    set -x
    peer chaincode upgrade -o orderer.upstac.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n common -l ${LANGUAGE} -v ${VERSION} -p ${CC_SRC_PATH} -c '{"Args":["org.upstac.user:instantiate"]}' -P "OR ('hospitalAMSP.member','hospitalBMSP.member')" >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Chaincode upgrade on peer${PEER}.${ORG} has failed"
  echo "===================== Chaincode is upgraded on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

upgradeChaincodeInsurance() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG
  VERSION=$3
  CHANNEL_NAME="insurance-hospitala"

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer chaincode upgrade -o orderer.upstac.com:7050 -C $CHANNEL_NAME -n insure -l ${LANGUAGE} -v ${VERSION} -p ${CC_SRC_PATH} -c '{"Args":["org.upstac.insurance:instantiate"]}' -P "OR ('hospitalAMSP.member','insuranceMSP.member')" >&log.txt
    res=$?
    set +x
  else
    set -x
    peer chaincode upgrade -o orderer.upstac.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n insure -l ${LANGUAGE} -v ${VERSION} -p ${CC_SRC_PATH} -c '{"Args":["org.upstac.insurance:instantiate"]}' -P "OR ('hospitalAMSP.member','insuranceMSP.member')" >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Chaincode upgrade on peer${PEER}.${ORG} has failed"
  echo "===================== Chaincode is upgraded on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

chaincodeQuery() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG
  EXPECTED_RESULT=$3
  echo "===================== Querying on peer${PEER}.${ORG} on channel '$CHANNEL_NAME'... ===================== "
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while
    test "$(($(date +%s) - starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
    sleep $DELAY
    echo "Attempting to Query peer${PEER}.${ORG} ...$(($(date +%s) - starttime)) secs"
    set -x
    peer chaincode query -C $CHANNEL_NAME -n common -c '{"Args":["org.upstac.user:instantiate"]}' >&log.txt
    res=$?
    set +x
    test $res -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
    # removed the string "Query Result" from peer chaincode query command
    # result. as a result, have to support both options until the change
    # is merged.
    test $rc -ne 0 && VALUE=$(cat log.txt | egrep '^[0-9]+$')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
  done
  echo
  cat log.txt
  if test $rc -eq 0; then
    echo "===================== Query successful on peer${PEER}.${ORG} on channel '$CHANNEL_NAME' ===================== "
  else
    echo "!!!!!!!!!!!!!!! Query result on peer${PEER}.${ORG} is INVALID !!!!!!!!!!!!!!!!"
    echo "================== ERROR !!! FAILED to query Chaincode on Certification Network =================="
    echo
    exit 1
  fi
}

# fetchChannelConfig <channel_id> <output_json>
# Writes the current channel config for a given channel to a JSON file
fetchChannelConfig() {
  CHANNEL=$1
  OUTPUT=$2

  setOrdererGlobals

  echo "Fetching the most recent configuration block for the channel"
  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer channel fetch config config_block.pb -o orderer.upstac.com:7050 -c $CHANNEL --cafile $ORDERER_CA
    set +x
  else
    set -x
    peer channel fetch config config_block.pb -o orderer.upstac.com:7050 -c $CHANNEL --tls --cafile $ORDERER_CA
    set +x
  fi

  echo "Decoding config block to JSON and isolating config to ${OUTPUT}"
  set -x
  configtxlator proto_decode --input config_block.pb --type common.Block | jq .data.data[0].payload.data.config >"${OUTPUT}"
  set +x
}

# createConfigUpdate <channel_id> <original_config.json> <modified_config.json> <output.pb>
# Takes an original and modified config, and produces the config update tx
# which transitions between the two
createConfigUpdate() {
  CHANNEL=$1
  ORIGINAL=$2
  MODIFIED=$3
  OUTPUT=$4

  set -x
  configtxlator proto_encode --input "${ORIGINAL}" --type common.Config >original_config.pb
  configtxlator proto_encode --input "${MODIFIED}" --type common.Config >modified_config.pb
  configtxlator compute_update --channel_id "${CHANNEL}" --original original_config.pb --updated modified_config.pb >config_update.pb
  configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate >config_update.json
  echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . >config_update_in_envelope.json
  configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope >"${OUTPUT}"
  set +x
}

# signConfigtxAsPeerOrg <org> <configtx.pb>
# Set the peerOrg admin of an org and signing the config update
signConfigtxAsPeerOrg() {
  PEERORG=$1
  TX=$2
  setGlobals 0 $PEERORG
  set -x
  peer channel signconfigtx -f "${TX}"
  set +x
}

chaincodeInvoke() {
  parsePeerConnectionParameters $@
  res=$?
  verifyResult $res "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

  # while 'peer chaincode' command can get the orderer endpoint from the
  # peer (if join was successful), let's supply it directly as we know
  # it using the "-o" option
  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer chaincode invoke -o orderer.upstac.com:7050 -C $CHANNEL_NAME -n upstac $PEER_CONN_PARMS -c '{"Args":["org.upstac.user:instantiate"]}' --isInit >&log.txt
    res=$?
    set +x
  else
    set -x
    peer chaincode invoke -o orderer.upstac.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n upstac $PEER_CONN_PARMS -c '{"Args":["org.upstac.user:instantiate"]}' --isInit >&log.txt
    res=$?
    set +x
  fi
  cat log.txt
  verifyResult $res "Invoke execution on $PEERS failed "
  echo "===================== Invoke transaction successful on $PEERS on channel '$CHANNEL_NAME' ===================== "
  echo
}

# parsePeerConnectionParameters $@
# Helper function that takes the parameters from a chaincode operation
# (e.g. invoke, query, instantiate) and checks for an even number of
# peers and associated org, then sets $PEER_CONN_PARMS and $PEERS
parsePeerConnectionParameters() {
  # check for uneven number of peer and org parameters
  if [ $(($# % 2)) -ne 0 ]; then
    exit 1
  fi

  PEER_CONN_PARMS=""
  PEERS=""
  while [ "$#" -gt 0 ]; do
    setGlobals $1 $2
    PEER="peer$1.$2"
    PEERS="$PEERS $PEER"
    PEER_CONN_PARMS="$PEER_CONN_PARMS --peerAddresses $CORE_PEER_ADDRESS"
    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "true" ]; then
      TLSINFO=$(eval echo "--tlsRootCertFiles \$PEER$1_$2_CA")
      PEER_CONN_PARMS="$PEER_CONN_PARMS $TLSINFO"
    fi
    # shift by two to get the next pair of peer/org parameters
    shift
    shift
  done
  # remove leading space for output
  PEERS="$(echo -e "$PEERS" | sed -e 's/^[[:space:]]*//')"
}

