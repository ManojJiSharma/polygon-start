#!/usr/bin/env bash
#set -e


# Truncate config.log file
> config.log

###################
## Configuration ##
###################

BaseDirectory="${1-$PWD}"
LogFile="$BaseDirectory/config.log"
CodeDirectory="$BaseDirectory"
BorDirectory="$CodeDirectory/bor"
HeimdallDirectory="$CodeDirectory/heimdall"
ContractDirectory="$CodeDirectory/contract"
GenesisContractDirectory="$CodeDirectory/genesis-contract"

# default parameters readed from matic-cli-config.yml 
defaultStake=$(yq eval '.defaultStake' matic-cli-config.yml)
defaultFee=$(yq eval '.defaultFee' matic-cli-config.yml)
borChainId=$(yq eval '.borChainId' matic-cli-config.yml)
heimdallChainId=$(yq eval '.heimdallChainId' matic-cli-config.yml)
contractsBranch=$(yq eval '.contractsBranch' matic-cli-config.yml)
genesisContractsBranch=$(yq eval '.genesisContractsBranch' matic-cli-config.yml)
sprintSize=$(yq eval '.sprintSize' matic-cli-config.yml)
blockNumber=$(yq eval '.blockNumber' matic-cli-config.yml)
blockTime=$(yq eval '.blockTime' matic-cli-config.yml)
numOfBorValidators=$(yq eval '.numOfBorValidators' matic-cli-config.yml)
numOfBorSentries=$(yq eval '.numOfBorSentries' matic-cli-config.yml)
numOfBorArchiveNodes=$(yq eval '.numOfBorArchiveNodes' matic-cli-config.yml)
numOfErigonValidators=$(yq eval '.numOfErigonValidators' matic-cli-config.yml)
numOfErigonSentries=$(yq eval '.numOfErigonSentries' matic-cli-config.yml)
numOfErigonArchiveNodes=$(yq eval '.numOfErigonArchiveNodes' matic-cli-config.yml)
ethURL=$(yq eval '.ethURL' matic-cli-config.yml)
ethHostUser=$(yq eval '.ethHostUser' matic-cli-config.yml)
devnetType=$(yq eval '.devnetType' matic-cli-config.yml)
borDockerBuildContext=$(yq eval '.borDockerBuildContext' matic-cli-config.yml)
heimdallDockerBuildContext=$(yq eval '.heimdallDockerBuildContext' matic-cli-config.yml)
sprintSizeBlockNumber=$(yq eval '.sprintSizeBlockNumber' matic-cli-config.yml)



#######################
### HELPER FUNCTIONS ##
#######################
# Setup console colors
if test -t 1 && which tput >/dev/null 2>&1; then
    ncolors=$(tput colors)
    if test -n "$ncolors" && test $ncolors -ge 8; then
        bold_color=$(tput bold)
        warn_color=$(tput setaf 3)
        error_color=$(tput setaf 1)
        reset_color=$(tput sgr0)
    fi
    # 72 used instead of 80 since that's the default of pr
    ncols=$(tput cols)
fi
: ${ncols:=72}

log(){
    printf '%s\n' "$@" >> "$LogFile"
}

log_cmd(){
  log "$(printf '%s $ %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$1")"
}

warn(){
  log "WARNING: $*"
  echo "$warn_color$bold_color$*$reset_color"
}

die(){
  log "ERROR: $*"
  echo "$error_color$bold_color$*$reset_color"
  exit 1
}

failed_command(){
  echo "$error_color${bold_color}Failed executing command:$reset_color $warn_color$1$reset_color"
  echo "check the config.log for more information"
  exit 1
}

exec_cmd() {
    log_cmd "$1"
    eval "{ $1 ;} > >(tee -a '$LogFile') 2> >(tee -a '$LogFile')" &> /dev/null || failed_command "$1";
    log ""
}

file_replace() {
    local regex="$1"
    local replacement="$2"
    local inputFile="$3"
    local outputFile="$4"

    file_exists "$inputFile"
    if [[ "$outputFile" == '' ]]; then
      if [[ ! -f "$inputFile.backup" ]]; then
        exec_cmd "mv '$inputFile' '$inputFile.backup'"
      fi
      outputFile="$inputFile"
      inputFile="$inputFile.backup"
    fi

    exec_cmd "sed -re 's/$regex/$replacement/gi' '$inputFile' > '$outputFile'"
}

test_cmd(){
    log "$@"
    "$@" >> "$LogFile" 2>&1
}

file_exists() {
  if [[ ! -f "$1" ]]; then
      die "File not found: \"$1\""
  fi
}

directory_exists() {
  if [[ ! -d "$1" ]]; then
      die "Directory not found: \"$1\""
  fi
}

# Using a pwd+dirname instead of realpath because of an issue on macos
# http://biercoff.com/readlink-f-unrecognized-option-problem-solution-on-mac/
resolve_path() {
  local absolutePath
  if [[ -f "$1" ]]; then
      local fileName
      fileName=$(basename -- "$1")
      absolutePath=$(dirname -- "$1") # relative
      absolutePath=$(cd -- "$absolutePath" && pwd) # absolutized and normalized
      absolutePath="$absolutePath/$fileName"       # fully qualified path
  elif [[ -d "$1" ]]; then
    absolutePath=$(cd -- "$1" && pwd) # absolutized and normalized
  else
      die "File or directory not found: \"$1\""
  fi
  echo "$absolutePath"
}

check_repository() {
  local directoryPath
  local expectedGitUrl

  directoryPath=$(resolve_path "$1")
  expectedGitUrl="$2"

  # Check if the directory exists
  if [[ ! -d "$directoryPath" ]]; then
      die "Directory not found: \"$1\""
  fi

  local gitUrl
  gitUrl=$(cd -- "$directoryPath" && git config --get remote.origin.url)

  # Check if the directory is a git repository
  if [[ "$gitUrl" != "$expectedGitUrl" ]]; then
      echo "The expect git repository doesn't match."
      warn " expect: \"$expectedGitUrl\""
      warn " actual: \"$gitUrl\""
      exit 1
  fi
}

##########################
### CHECK DEPENDENCIES ###
##########################
if ! command -v go &> /dev/null; then
    die "Golang not found, install it from https://golang.org/dl/"
fi

if ! command -v node &> /dev/null; then
    die "Nodejs not found, install it from https://nodejs.org/en"
fi

if ! command -v solc &> /dev/null; then
    die "Solc v0.5.17 not found"
fi

if ! command -v jq &> /dev/null; then
    echo "$error_color${bold_color}jq not found.$reset_color"
    echo " For MacOs: brew install jq"
    echo "For Debian: apt-get install jq"
    exit 1
fi

# Checkout Bor, Heimdall, Genesis-contract and contract code
if [[ ! -d "$BorDirectory" ]]; then
  exec_cmd "mkdir -p '$BorDirectory'"
  exec_cmd "git clone 'https://github.com/maticnetwork/bor.git' --branch 'v0.4.0' --depth 1 '$BorDirectory'"
fi

if [[ ! -d "$HeimdallDirectory" ]]; then
  exec_cmd "mkdir -p '$HeimdallDirectory'"
  exec_cmd "git clone 'https://github.com/maticnetwork/heimdall.git' --branch 'v0.3.4' --depth 1 '$HeimdallDirectory'"
fi

if [[ ! -d "$GenesisContractDirectory" ]]; then
  exec_cmd "mkdir -p '$GenesisContractDirectory'"
  exec_cmd "git clone 'https://github.com/maticnetwork/genesis-contracts.git' --branch 'master' --depth 1 '$GenesisContractDirectory'"
fi

if [[ ! -d "$ContractDirectory" ]]; then
  exec_cmd "mkdir -p '$ContractDirectory'"
  exec_cmd "git clone 'https://github.com/maticnetwork/contracts.git' --branch 'develop' --depth 1 '$ContractDirectory'"
fi


# Check if the repository folders are valid
check_repository "$BorDirectory" 'https://github.com/maticnetwork/bor.git'
check_repository "$HeimdallDirectory" 'https://github.com/maticnetwork/heimdall.git'
check_repository "$GenesisContractDirectory" 'https://github.com/maticnetwork/genesis-contracts.git'
check_repository "$ContractDirectory" 'https://github.com/maticnetwork/contracts.git'



# Convert relative paths to absolute paths
BorDirectory=$(resolve_path "$BorDirectory")
HeimdallDirectory=$(resolve_path "$HeimdallDirectory")
GenesisContractDirectory=$(resolve_path "$GenesisContractDirectory")
ContractDirectory=$(resolve_path "$ContractDirectory")



#############################
### SETUP POLYGON TESTNET ###
#############################
build_heimdall() {

  if [[ -f "$HeimdallDirectory/build/heimdalld" ]] && [[ -f "$HeimdallDirectory/build/heimdallcli" ]]; then
    echo "Skipping Heimdall build..."
    return
  fi

  echo "Building Heimdall..."
  exec_cmd "cd '$HeimdallDirectory'"
  [[ -d 'build' ]] && exec_cmd 'rm -rf build'
  exec_cmd 'mkdir -p build' || die "cannot create build directory at \"$HeimdallDirectory/build\""

  exec_cmd "make build"

  # Check if the binaries exists
  file_exists './build/heimdalld'
  file_exists './build/heimdallcli'

  # Print version
  exec_cmd './build/heimdalld version'
  exec_cmd './build/heimdallcli version'

  echo "Heimdall built successfully!!"
}

build_bor() {
  echo "Building Bor..."
  exec_cmd "cd '$BorDirectory'"
  exec_cmd 'make bor'
  echo "Bor built successfully!!"
}


create_test_file_for_heimdall() {
  echo "Create testnet files for Heimdall"
  exec_cmd "$HeimdallDirectory/build/heimdalld init --chain devnet --home $BaseDirectory/devnet"
  exec_cmd "$HeimdallDirectory/build/heimdalld create-testnet --home devnet --v $(($numOfBorValidators + $numOfErigonValidators))  --n $(($numOfBorSentries + $numOfBorArchiveNodes + $numOfErigonSentries + $numOfErigonArchiveNodes)) --chain-id $heimdallChainId --node-host-prefix heimdall --output-dir devnet"
  
  for ((i = 0; i < $numOfBorValidators; i++)); do
    # exec_cmd "rm -rf $BaseDirectory/devnet/node${i}"
    exec_cmd "$HeimdallDirectory/build/heimdalld init --chain devnet --home $BaseDirectory/devnet/node${i}"
  done
}


# setup_account(){

# }

setup_genesis_contract() {
  # Install dependencies and submodules
  exec_cmd "cd $GenesisContractDirectory"
  exec_cmd "npm install"
  exec_cmd "git submodule init"
  exec_cmd "git submodule update"

  #Compile Matic contracts
  exec_cmd "cd matic-contracts"
  exec_cmd "npm install"
  exec_cmd "node scripts/process-templates.js --bor-chain-id $borChainId"
  exec_cmd "npm run truffle:compile"
  exec_cmd "cd .."

  # Generate Bor validator set sol file
  exec_cmd "node generate-borvalidatorset.js --bor-chain-id $borChainId --heimdall-chain-id $heimdallChainId"

  #Compile contracts
  exec_cmd "npm run truffle:compile"

  #Generate genesis file
  exec_cmd "node generate-genesis.js  --bor-chain-id $borChainId --heimdall-chain-id $heimdallChainId"

}


# setup_bor_erigon_keystore_genesis_file() {

# }

setup_contracts_on_ganache() {
  
}


build_heimdall
build_bor
create_test_file_for_heimdall
# setup_account
setup_genesis_contract
# setup_bor_erigon_keystore_genesis_file
setup_contracts_on_ganache