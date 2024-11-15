#set -g fish_trace 1


#Before calling set: 
#     ONRAMP_CODE_PATH,
#     LOTUS_EXEC_PATH,
#     BOOST_EXEC_PATH,
#     XCHAIN_KEY_PATH,
#     XCHAIN_PASSPHRASE,
#     XCHAIN_ETH_API
#     MINER_ADDRESS
#   
# Deploys contracts needed for onramp demo
# Sets up config for data-client and xchain-connector
function deploy-onramp
	# Build bytecode from source
	cd $ONRAMP_CODE_PATH
	forge build
	set bcProver (get-bytecode /home/ubuntu/onramp-contracts/out/Prover.sol/DealClient.json)
	set bcOracle (get-bytecode /home/ubuntu/onramp-contracts/out/Oracles.sol/ForwardingProofMockBridge.json)
	set bcOnRamp (get-bytecode /home/ubuntu/onramp-contracts/out/OnRamp.sol/OnRampContract.json)

	# Deploy contracts to local network
	cd $LOTUS_EXEC_PATH
	echo $bcProver > prover.bytecode
	echo $bcOracle > oracle.bytecode
	echo $bcOnRamp > onramp.bytecode
	set proverOut (lotus evm deploy --hex prover.bytecode)
	set oracleOut (lotus evm deploy --hex oracle.bytecode)
	set onrampOut (lotus evm deploy --hex onramp.bytecode)

	set proverIDAddr (parse-id-address $proverOut)
	set oracleIDAddr (parse-id-address $oracleOut)
	set onrampIDAddr (parse-id-address $onrampOut)
	set -x proverAddr (parse-address $proverOut)
	set -x oracleAddr (parse-address $oracleOut)
	set -x onrampAddr (parse-address $onrampOut)


	echo "Prover Contract Address: $proverAddr"
	echo "Oracle Contract Address: $oracleAddr"
	echo "OnRamp Contract Address: $onrampAddr"
	echo "Prover ID Address: $proverIDAddr"
	echo "Oracle ID Address: $oracleIDAddr"
	echo "OnRamp ID Address: $onrampIDAddr"

	# Print out Info
	echo -e "~*~*~Oracle~*~*~\n"
	string join \n $oracleOut[3..]
	echo -e "\n"
	echo -e "~*~*~Prover~*~*~\n"
	string join \n $proverOut[3..]
	echo -e "\n"	 
	echo -e "~*~*~OnRamp~*~*~\n"
	string join \n $onrampOut[3..]
	echo -e "\n"

	# Wire contracts up together
	echo -e "~*~*~Connect Oracle to Prover\n"
	set calldataProver (cast calldata "setBridgeContract(address)" $oracleAddr)
	lotus evm invoke $proverIDAddr $calldataProver

	echo -e "\n~*~*~Connect Oracle to OnRamp\n"
	set calldataOnRamp (cast calldata "setOracle(address)" $oracleAddr)
	lotus evm invoke $onrampIDAddr $calldataOnRamp

	echo -e "\n~*~*~Connect Prover and OnRamp to Oracle\n"
	set callDataOracle (cast calldata "setSenderReceiver(string,address)" $proverAddr $onrampAddr)
	lotus evm invoke $oracleIDAddr $callDataOracle

	# Setup xchain config
	mkdir -p ~/.xchain

	cd $LOTUS_EXEC_PATH
	# Parse address from eth keystore file 
	set clientAddr (cat $XCHAIN_KEY_PATH | jq '.address' | sed -e 's/\"//g')
	echo "clientAddr: $clientAddr"
	set filClientAddr (parse-filecoin-address (lotus evm stat $clientAddr))
	echo "filClientAddr: $filClientAddr"

	#./lotus state wait-msg --timeout "2m" (./lotus send $filClientAddr 20)
	cd $ONRAMP_CODE_PATH
	jq -c '.abi' /home/ubuntu/onramp-contracts/out/OnRamp.sol/OnRampContract.json > ~/.xchain/onramp-abi.json

    # chain id and lotus api url is hard coded and will be a source of bugs when moved away from calibnet
	jo -a (jo -- ChainID=314159 Api="$XCHAIN_ETH_API" -s OnRampAddress="$onrampAddr" \
		KeyPath="$XCHAIN_KEY_PATH" ClientAddr="$clientAddr" OnRampABIPath=~/.xchain/onramp-abi.json \
		BufferPath=~/.xchain/buffer BufferPort=5077 ProviderAddr="$MINER_ADDRESS" \
		LotusAPI="http://localhost:1234" -s ProverAddr="$proverAddr" \
		-s PayoutAddr="0x0C0FFEEC0FFEEC0FFEEC0FFEEC0FFEEC0FEECAFE") > ~/.xchain/config.json
	echo "config written to ~/.xchain/config.json" 
	deploy-tokens $onrampAddr
end

#  $argv[1] path to compiled file
function get-bytecode
	 # Strip extra jq quotes and "0x" 
	 jq '.bytecode.object' $argv[1] | sed -e 's/0x//g ; s/\"//g'
end

#  $argv string output of lotus evm deploy 
function parse-address
	echo $argv | sed -En 's/.*Eth Address: +(0x[a-f0-9]+).*/\1/p'
end

#  $argv string output of cast contract create display
function parse-address-cast-create
	echo $argv | sed -En 's/.*contractAddress[[:space:]]+([0-9a-fA-Fx]+).*/\1/p'
end

function parse-id-address
	echo $argv | sed -En 's/.*ID Address: +([tf]0[0-9]+).*/\1/p'
end

function parse-filecoin-address
	echo $argv | sed -En 's/.*Filecoin address: +([tf]4[a-z0-9]+).*/\1/p'
end
function deploy-tokens
	 cd $ONRAMP_CODE_PATH
	 forge build
	 set bcNickle (get-bytecode /home/ubuntu/onramp-contracts/out/Token.sol/Nickle.json)
	 set bcCowry (get-bytecode /home/ubuntu/onramp-contracts/out/Token.sol/BronzeCowry.json)
	 set bcPound (get-bytecode /home/ubuntu/onramp-contracts/out/Token.sol/DebasedTowerPoundSterling.json)

	 # Approve 10^9 tokens allowance for onramp contract
	 set approveCallData (cast calldata "approve(address,uint256)" $argv[1] 1000000000)

	 cd $LOTUS_EXEC_PATH
	 echo $bcNickle > nickle.bytecode
	 echo $bcCowry > cowry.bytecode
	 echo $bcPound > pound.bytecode

	 ascii-five
	 echo -e "~$0.05~$0.05~ 'NICKLE' ~$0.05~$0.05~\n"
	 set nickleCreate (cast send --gas-limit 10000000000 --keystore $XCHAIN_KEY_PATH --password "$XCHAIN_PASSPHRASE" --rpc-url $XCHAIN_ETH_API --create $bcNickle)
     sleep 1m
	 string join \n $nickleCreate
	 echo $nickleCreate[1..3]
	 set nickleAddr (parse-address-cast-create $nickleCreate)
	 cast send --gas-limit 10000000000 --keystore $XCHAIN_KEY_PATH --password "$XCHAIN_PASSPHRASE" --rpc-url $XCHAIN_ETH_API $nickleAddr $approveCallData
     sleep 1m

	 ascii-shell
	 echo -e "~#!~#!~ 'SHELL' ~#!~#!~\n"	 
	 set cowryCreate (cast send --gas-limit 10000000000 --keystore $XCHAIN_KEY_PATH --password "$XCHAIN_PASSPHRASE" --rpc-url $XCHAIN_ETH_API --create $bcCowry)
     sleep 1m

     string join \n $cowryCreate
	 set cowryAddr (parse-address-cast-create $cowryCreate)

	 cast send --gas-limit 10000000000 --keystore $XCHAIN_KEY_PATH --password "$XCHAIN_PASSPHRASE" --rpc-url $XCHAIN_ETH_API $cowryAddr $approveCallData
     sleep 1m

	 ascii-union-jack	 
	 echo -e "~#L~#L~ 'NEWTON' ~#L~#L~\n"
	 set poundCreate (cast send --gas-limit 10000000000 --keystore $XCHAIN_KEY_PATH --password "$XCHAIN_PASSPHRASE" --rpc-url $XCHAIN_ETH_API --create $bcPound) 
     sleep 1m

	 string join \n $poundCreate
	 set poundAddr (parse-address-cast-create $poundCreate)
	 cast send --gas-limit 10000000000 --keystore $XCHAIN_KEY_PATH --password "$XCHAIN_PASSPHRASE" --rpc-url $XCHAIN_ETH_API $poundAddr $approveCallData
     sleep 1m

end

# Some ASCII logos to give our erc20s character
function ascii-five
	 echo "
                 ____  
                | ___| 
                |___ \ 
                 ___) |
                |____/ 

"
end

function ascii-shell
	 echo -e "
                  /\\
                 {.-}
                ;_,-'\\
               {    _.}_      
                \.-' /  `,
                 \  |    /
                  \ |  ,/
                   \|_/

"
end

function ascii-union-jack
	 echo -e "
⢿⣦⣌⠙⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⣿⣿⣿⡇⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠋⣡⣴⡿
⣦⡈⠛⢿⣶⣄⡙⠻⣿⣿⣿⣿⣿⣿⠀⣿⣿⣿⡇⣿⣿⣿⣿⣿⣿⠟⢋⣠⣶⡿⠛⢁⣤
⣿⣿⣷⣤⡈⠛⢿⣶⣄⡙⠻⢿⣿⣿⠀⣿⣿⣿⡇⣿⣿⣿⠟⢋⣠⣶⡿⠛⢁⣤⣾⣿⣿
⣿⣿⣿⣿⣿⣷⣦⣈⠙⠿⠷⠤⠉⠻⠀⣿⣿⣿⡇⠟⠉⠤⠾⠿⠋⣁⣤⣾⣿⣿⣿⣿⣿
⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣿⣿⣿⣇⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⣿⣿⣿⡿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿
⣿⣿⣿⣿⣿⣿⠟⠋⣀⣴⡶⠖⢀⣤⠀⣿⣿⣿⡇⣤⡀⠲⢶⣦⣄⠙⠻⣿⣿⣿⣿⣿⣿
⣿⣿⣿⠟⠋⣠⣴⡿⠟⢉⣤⣾⣿⣿⠀⣿⣿⣿⡇⣿⣿⣷⣤⡉⠻⢿⣦⣄⠙⠻⣿⣿⣿
⠟⠋⣠⣴⡿⠛⣉⣤⣾⣿⣿⣿⣿⣿⠀⣿⣿⣿⡇⣿⣿⣿⣿⣿⣷⣤⣈⠛⢿⣦⣄⡙⠻
⣶⠿⠛⣁⣴⣾⣿⣿⣿⣿⣿⣿⣿⣿⠀⣿⣿⣿⡇⣿⣿⣿⣿⣿⣿⣿⣿⣷⣦⣈⠙⠿⣶


	 "

end